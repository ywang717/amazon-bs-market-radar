# Amazon BS Market Radar V2 Phase 1 数据语义实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Raw Amazon Ranking 和现有采集链路的前提下，实现统一的 Market Context、Product Classification、Brand Normalization、Valid Market Day 和跨 PostgreSQL/D1 的产品元数据同步。

**Architecture:** 本地 PowerShell 语义模块是产品分类、品牌标准化和文件历史有效日选择的权威实现；PostgreSQL 保存独立的 Best Sellers Product Metadata，并提供 Valid Category Day 查询原语；网站 TypeScript 负责解析 Market Context、消费已同步元数据并根据 D1 的持久完整标记与 Exact Top30 双重选择有效市场日。Raw Observation 不增加分类或品牌字段，Analytical Market 通过独立 Metadata Join 形成。

**Tech Stack:** Windows PowerShell 5.1、Pester 3.4、PostgreSQL SQL/PLpgSQL、TypeScript 5.9、React 19、vinext、Cloudflare D1/SQLite、Drizzle ORM、Node Test Runner。

**Spec:** `docs/superpowers/specs/2026-08-27-v2-phase1-data-semantics-design.md`

## 全局约束

- 仅执行 Phase 1，不实现任何 Phase 2 指标或 V2 业务页面。
- 不重写 `scripts/python/collect_best_sellers.py`，不改变 Raw Snapshot 或 Raw Ranking 语义。
- 不从 Title 推断 Brand；没有 Verified Brand 时保存 null，UI 语义为 Unknown。
- Product Classification 必须允许 `unknown/low`，所有规则集中、版本化、可解释。
- Valid Market Day 必须同时满足持久化 Complete 标记与 Exact Top30 校验。
- Price、Rating、Reviews、Discount 缺失不影响排名市场日有效性。
- 失败的 2026-08-19 必须被跳过，2026-08-18 与 2026-08-20 是相邻有效市场日。
- PostgreSQL 只新增迁移，禁止修改 `db/migrations/001`–`011`。
- D1 Schema、Drizzle Migration、运行时 `ensureSchema` 和 Sync Contract 必须同步升级。
- 所有生产代码严格遵守 Red → Green → Refactor；每个新行为必须先看到测试因功能缺失而失败。
- 所有 Git 提交只包含当前 Task 的相关文件，不提交现有 `AGENTS.md` 或无关工作树改动。
- 所有 `web` Node/pnpm 命令均从仓库根目录先执行 `$nodeBin='C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'; Push-Location .\web`，完成该 Task 后执行 `Pop-Location`；计划中的 `$nodeBin` 均指此路径。

---

### Task 1：集中规则、产品分类与品牌标准化

**Files:**

- Create: `config/v2-product-classification.json`
- Create: `config/v2-brand-aliases.json`
- Create: `src/BestSellersDataSemantics.psm1`
- Create: `tests/BestSellersDataSemantics.Tests.ps1`

**Interfaces:**

- Consumes: Raw observation 的 `asin`、`title`、`category_key`；可选 Verified Raw Brand 与 Brand Source。
- Produces: `Get-BestSellersProductClassification`、`Get-BestSellersBrandNormalization`，供 Task 3、6、7 使用。

- [ ] **Step 1：写 Product Classification 失败测试**

在 `tests/BestSellersDataSemantics.Tests.ps1` 中创建真实规则测试：

```powershell
$modulePath = Join-Path $PSScriptRoot '..\src\BestSellersDataSemantics.psm1'
Import-Module $modulePath -Force

Describe 'V2 product classification' {
    $configPath = Join-Path $PSScriptRoot '..\config\v2-product-classification.json'

    $cases = @(
        @{ Title='Westinghouse Electric Pressure Washer 2500 PSI'; Category='pressure_washers'; Type='electric_pressure_washer'; Confidence='high' },
        @{ Title='Gas Pressure Washer 3200 PSI'; Category='pressure_washers'; Type='gas_pressure_washer'; Confidence='high' },
        @{ Title='Cordless Battery Powered Pressure Washer'; Category='pressure_washers'; Type='cordless_pressure_washer'; Confidence='high' },
        @{ Title='15 Inch Pressure Washer Surface Cleaner'; Category='pressure_washers'; Type='surface_cleaner'; Confidence='high' },
        @{ Title='Pressure Washer Gun and Wand Kit'; Category='pressure_washers'; Type='pressure_washer_gun'; Confidence='high' },
        @{ Title='50 FT Pressure Washer Hose'; Category='pressure_washers'; Type='hose'; Confidence='high' },
        @{ Title='5 Pack Pressure Washer Nozzle Tips'; Category='pressure_washers'; Type='nozzle'; Confidence='high' },
        @{ Title='Pressure Washer Chemical Cleaner Concentrate'; Category='pressure_washers'; Type='chemical_cleaner'; Confidence='high' },
        @{ Title='Pump Protector for Pressure Washers'; Category='pressure_washers'; Type='pump_protector'; Confidence='high' },
        @{ Title='Universal Pressure Washer Replacement Accessory'; Category='pressure_washer_accessories'; Type='other_accessory'; Confidence='medium' },
        @{ Title='Outdoor Cleaning Tool'; Category='pressure_washers'; Type='unknown'; Confidence='low' }
    )

    foreach ($case in $cases) {
        It "classifies $($case.Type)" {
            $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title $case.Title -CategoryKey $case.Category -ConfigPath $configPath
            $result.product_type | Should Be $case.Type
            $result.classification_confidence | Should Be $case.Confidence
            $result.rule_version | Should Be 'product-rules-v1'
            @($result.evidence).Count | Should BeGreaterThan 0
        }
    }

    It 'lets a specific accessory rule win over a broad machine phrase' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Electric Pressure Washer Hose Replacement 50 FT' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'hose'
    }

    It 'returns unknown low for conflicting machine evidence' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Gas Electric Cordless Pressure Washer' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'unknown'
        $result.classification_confidence | Should Be 'low'
        @($result.evidence | Where-Object { $_ -like 'CONFLICT:*' }).Count | Should BeGreaterThan 0
    }
}
```

- [ ] **Step 2：运行测试并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1
```

Expected: FAIL，原因是 `BestSellersDataSemantics.psm1` 或 `Get-BestSellersProductClassification` 尚不存在，而不是测试语法错误。

- [ ] **Step 3：新增集中 Product Classification Config**

`config/v2-product-classification.json` 使用以下完整结构；关键词均为不区分大小写的简单短语，避免 PowerShell 与 JavaScript Regex 方言差异：

```json
{
  "schema_version": "product-classification-config-v1",
  "rule_version": "product-rules-v1",
  "rules": [
    { "id": "accessory-surface-cleaner", "product_type": "surface_cleaner", "confidence": "high", "category_keys": ["pressure_washers", "pressure_washer_accessories"], "any_phrases": ["surface cleaner"] },
    { "id": "accessory-gun", "product_type": "pressure_washer_gun", "confidence": "high", "category_keys": ["pressure_washers", "pressure_washer_accessories"], "any_phrases": ["pressure washer gun", "spray gun", "wand kit"] },
    { "id": "accessory-hose", "product_type": "hose", "confidence": "high", "category_keys": ["pressure_washers", "pressure_washer_accessories"], "any_phrases": ["pressure washer hose", "replacement hose"] },
    { "id": "accessory-nozzle", "product_type": "nozzle", "confidence": "high", "category_keys": ["pressure_washers", "pressure_washer_accessories"], "any_phrases": ["nozzle tip", "nozzle tips", "spray nozzle"] },
    { "id": "accessory-chemical", "product_type": "chemical_cleaner", "confidence": "high", "category_keys": ["pressure_washers", "pressure_washer_accessories"], "any_phrases": ["chemical cleaner", "cleaning concentrate", "pressure washer soap"] },
    { "id": "accessory-pump-protector", "product_type": "pump_protector", "confidence": "high", "category_keys": ["pressure_washers", "pressure_washer_accessories"], "any_phrases": ["pump protector"] },
    { "id": "machine-cordless", "product_type": "cordless_pressure_washer", "confidence": "high", "category_keys": ["pressure_washers"], "all_phrases": ["pressure washer"], "any_phrases": ["cordless", "battery powered", "battery-powered"] },
    { "id": "machine-gas", "product_type": "gas_pressure_washer", "confidence": "high", "category_keys": ["pressure_washers"], "all_phrases": ["pressure washer"], "any_phrases": ["gas", "gasoline"] },
    { "id": "machine-electric", "product_type": "electric_pressure_washer", "confidence": "high", "category_keys": ["pressure_washers"], "all_phrases": ["pressure washer"], "any_phrases": ["electric", "corded"] },
    { "id": "accessory-other", "product_type": "other_accessory", "confidence": "medium", "category_keys": ["pressure_washer_accessories"], "any_phrases": ["pressure washer", "replacement", "universal"] }
  ]
}
```

- [ ] **Step 4：实现最小 Product Classifier**

在 `src/BestSellersDataSemantics.psm1` 实现：

```powershell
function Get-BestSellersProductClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-Z0-9]{10}$')][string]$Asin,
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )

    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$config.schema_version -ne 'product-classification-config-v1') { throw 'Unsupported product classification config version.' }
    $normalizedTitle = (($Title.Trim() -replace '\s+', ' ').ToLowerInvariant())
    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($rule in @($config.rules)) {
        if ([string]$CategoryKey -notin @($rule.category_keys | ForEach-Object { [string]$_ })) { continue }
        $allMatch = @($rule.all_phrases).Count -eq 0 -or @($rule.all_phrases | Where-Object { $normalizedTitle.Contains(([string]$_).ToLowerInvariant()) }).Count -eq @($rule.all_phrases).Count
        $anyMatch = @($rule.any_phrases).Count -eq 0 -or @($rule.any_phrases | Where-Object { $normalizedTitle.Contains(([string]$_).ToLowerInvariant()) }).Count -gt 0
        if ($allMatch -and $anyMatch) { $matches.Add($rule) }
    }

    $accessoryTypes = @('surface_cleaner','pressure_washer_gun','hose','nozzle','chemical_cleaner','pump_protector')
    $accessoryMatches = @($matches | Where-Object { [string]$_.product_type -in $accessoryTypes })
    $specific = if ($accessoryMatches.Count -gt 0) { $accessoryMatches } else { @($matches | Where-Object { [string]$_.product_type -ne 'other_accessory' }) }
    $types = @($specific.product_type | Sort-Object -Unique)
    if ($types.Count -gt 1) {
        return [pscustomobject]@{ asin=$Asin; product_type='unknown'; classification_confidence='low'; rule_id=$null; rule_version=[string]$config.rule_version; evidence=@($specific | ForEach-Object { "CONFLICT:$([string]$_.id)" }) }
    }
    $winner = if ($specific.Count -gt 0) { $specific[0] } elseif ($matches.Count -gt 0) { $matches[0] } else { $null }
    if ($null -eq $winner) {
        return [pscustomobject]@{ asin=$Asin; product_type='unknown'; classification_confidence='low'; rule_id=$null; rule_version=[string]$config.rule_version; evidence=@('NO_SAFE_RULE_MATCH') }
    }
    return [pscustomobject]@{ asin=$Asin; product_type=[string]$winner.product_type; classification_confidence=[string]$winner.confidence; rule_id=[string]$winner.id; rule_version=[string]$config.rule_version; evidence=@("TITLE_RULE:$([string]$winner.id)") }
}
```

只导出公开函数，不在模块加载时读取 Config。

- [ ] **Step 5：运行 Product Classification 测试并确认 GREEN**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1
```

Expected: Product Classification tests PASS。

- [ ] **Step 6：写 Brand Normalization 失败测试**

在同一测试文件加入：

```powershell
Describe 'V2 brand normalization' {
    $configPath = Join-Path $PSScriptRoot '..\config\v2-brand-aliases.json'

    It 'normalizes case whitespace and an audited alias without changing raw brand' {
        $result = Get-BestSellersBrandNormalization -RawBrand '  WESTINGHOUSE Outdoor Power Equipment ' -Source verified_metadata -ConfigPath $configPath
        $result.raw_brand | Should Be 'WESTINGHOUSE Outdoor Power Equipment'
        $result.normalized_brand | Should Be 'Westinghouse'
        $result.normalized_key | Should Be 'westinghouse'
        $result.alias_rule_id | Should Be 'brand-westinghouse'
    }

    It 'returns unknown when no verified raw brand exists' {
        $result = Get-BestSellersBrandNormalization -RawBrand $null -Source unknown -ConfigPath $configPath
        $result.raw_brand | Should Be $null
        $result.normalized_brand | Should Be $null
        $result.source | Should Be 'unknown'
    }

    It 'rejects a raw brand whose source is unknown' {
        { Get-BestSellersBrandNormalization -RawBrand 'Westinghouse' -Source unknown -ConfigPath $configPath } | Should Throw
    }
}
```

- [ ] **Step 7：运行 Brand 测试并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1
```

Expected: FAIL，原因是 `Get-BestSellersBrandNormalization` 或 Alias Config 尚不存在。

- [ ] **Step 8：新增 Brand Alias Config 并实现 Normalizer**

`config/v2-brand-aliases.json`：

```json
{
  "schema_version": "brand-alias-config-v1",
  "aliases": [
    {
      "id": "brand-westinghouse",
      "canonical_name": "Westinghouse",
      "aliases": ["Westinghouse", "WESTINGHOUSE", "Westinghouse Outdoor Power Equipment"]
    }
  ]
}
```

实现 `Get-BestSellersBrandNormalization`：

```powershell
function Get-BestSellersBrandNormalization {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$RawBrand,
        [Parameter(Mandatory=$true)][ValidateSet('verified_metadata','manual_review','unknown')][string]$Source,
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )
    if ([string]::IsNullOrWhiteSpace($RawBrand)) {
        return [pscustomobject]@{ raw_brand=$null; normalized_brand=$null; normalized_key=$null; alias_rule_id=$null; source='unknown' }
    }
    if ($Source -eq 'unknown') { throw 'A raw brand requires a verified source.' }
    $raw = ($RawBrand.Trim() -replace '\s+', ' ')
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$config.schema_version -ne 'brand-alias-config-v1') { throw 'Unsupported brand alias config version.' }
    $key = $raw.ToLowerInvariant()
    $matched = @($config.aliases | Where-Object { @($_.aliases | ForEach-Object { (([string]$_).Trim() -replace '\s+', ' ').ToLowerInvariant() }) -contains $key })
    if ($matched.Count -gt 1) { throw 'Brand alias catalog contains an ambiguous alias.' }
    if ($matched.Count -eq 1) {
        $canonical = [string]$matched[0].canonical_name
        return [pscustomobject]@{ raw_brand=$raw; normalized_brand=$canonical; normalized_key=$canonical.ToLowerInvariant(); alias_rule_id=[string]$matched[0].id; source=$Source }
    }
    return [pscustomobject]@{ raw_brand=$raw; normalized_brand=$raw; normalized_key=$key; alias_rule_id=$null; source=$Source }
}
```

模块末尾：

```powershell
Export-ModuleMember -Function Get-BestSellersProductClassification, Get-BestSellersBrandNormalization
```

- [ ] **Step 9：运行 Task 1 测试并提交**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1
```

Expected: PASS，0 failures。

Commit:

```powershell
git add config/v2-product-classification.json config/v2-brand-aliases.json src/BestSellersDataSemantics.psm1 tests/BestSellersDataSemantics.Tests.ps1
git commit -m "feat: add v2 product and brand semantics"
```

---

### Task 2：Market Context 与网站 Analytical Market 过滤

**Files:**

- Create: `web/lib/market-context.ts`
- Create: `web/lib/product-metadata.ts`
- Create: `web/tests/market-context.test.mjs`
- Modify: `web/lib/catalog.ts`

**Interfaces:**

- Consumes: Task 1 定义的 Product Type 字符串；现有 `CategoryKey`。
- Produces: `parseMarketContext(url)`、`validateMarketContext(input)`、`filterAnalyticalMarket(rows, metadata, context)`、`ProductMetadata` 类型。

- [ ] **Step 1：写 Market Context 失败测试**

`web/tests/market-context.test.mjs`：

```js
import assert from "node:assert/strict";
import test from "node:test";
import { filterAnalyticalMarket, parseMarketContext } from "../lib/market-context.ts";

test("defaults to US pressure washers machines", () => {
  assert.deepEqual(parseMarketContext(new URL("https://example.test/")), {
    ok: true,
    context: { marketplace: "US", category: "pressure_washers", segment: "machines" },
  });
});

test("rejects an unsupported category segment combination", () => {
  assert.deepEqual(parseMarketContext(new URL("https://example.test/?marketplace=US&category=sump_pumps&segment=gas")), {
    ok: false,
    error: "unsupported_market_context",
  });
});

test("filters machines without changing raw rows", () => {
  const raw = [{ asin: "B000000001" }, { asin: "B000000002" }, { asin: "B000000003" }];
  const metadata = [
    { asin: "B000000001", productType: "electric_pressure_washer" },
    { asin: "B000000002", productType: "surface_cleaner" },
    { asin: "B000000003", productType: "unknown" },
  ];
  const result = filterAnalyticalMarket(raw, metadata, { marketplace: "US", category: "pressure_washers", segment: "machines" });
  assert.deepEqual(result.map(({ asin }) => asin), ["B000000001"]);
  assert.equal(raw.length, 3);
});
```

- [ ] **Step 2：运行测试并确认 RED**

Run:

```powershell
$nodeBin='C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
& "$nodeBin\node.exe" --test tests/market-context.test.mjs
```

Workdir: `web`

Expected: FAIL with module-not-found for `market-context.ts`。

- [ ] **Step 3：实现 Product Metadata 类型与 Market Context**

`web/lib/product-metadata.ts` 导出与 Sync Contract 一致的字符串联合类型：

```ts
export type ProductType = "electric_pressure_washer" | "gas_pressure_washer" | "cordless_pressure_washer" | "surface_cleaner" | "pressure_washer_gun" | "hose" | "nozzle" | "chemical_cleaner" | "pump_protector" | "other_accessory" | "unknown";
export type ClassificationConfidence = "high" | "medium" | "low";
export type BrandSource = "verified_metadata" | "manual_review" | "unknown";
export type ProductMetadata = {
  marketplace: "AMAZON_US";
  asin: string;
  productType: ProductType;
  classificationConfidence: ClassificationConfidence;
  classificationRuleId: string | null;
  classificationRuleVersion: string;
  classificationEvidence: string[];
  rawBrand: string | null;
  normalizedBrand: string | null;
  normalizedBrandKey: string | null;
  brandAliasRuleId: string | null;
  brandSource: BrandSource;
  firstSeenMarketDate: string;
  lastSeenMarketDate: string;
};
```

`web/lib/market-context.ts` 导出：

```ts
export type MarketplaceCode = "US";
export type SegmentKey = "all_bestsellers" | "machines" | "electric" | "gas" | "cordless" | "accessories";
export type MarketContext = { marketplace: MarketplaceCode; category: CategoryKey; segment: SegmentKey };
export type MarketContextResult = { ok: true; context: MarketContext } | { ok: false; error: "unsupported_market_context" };
export function validateMarketContext(input: { marketplace: string; category: string; segment: string }): MarketContextResult;
export function parseMarketContext(url: URL): MarketContextResult;
export function filterAnalyticalMarket<T extends { asin: string }>(rows: T[], metadata: Pick<ProductMetadata, "asin" | "productType">[], context: MarketContext): T[];
```

实现固定的 supported combination map；`all_bestsellers` 返回 `rows.slice()`，其它 Segment 根据 Product Type Set 筛选。禁止修改输入数组。

- [ ] **Step 4：运行 Market Context 测试并确认 GREEN**

Run:

```powershell
& "$nodeBin\node.exe" --test tests/market-context.test.mjs
```

Expected: PASS。

- [ ] **Step 5：更新 Catalog 并提交**

在 `web/lib/catalog.ts` 为现有 category 增加支持的 segment metadata，但保持原 `key/label/nodeId/short` 字段不变，避免破坏旧调用者。

Run:

```powershell
& "$nodeBin\node.exe" --test tests/market-context.test.mjs tests/analytics.test.mjs
```

Commit:

```powershell
git add web/lib/market-context.ts web/lib/product-metadata.ts web/lib/catalog.ts web/tests/market-context.test.mjs
git commit -m "feat: define v2 market context"
```

---

### Task 3：统一 Valid Market Day 选择器

**Files:**

- Modify: `src/BestSellersDataSemantics.psm1`
- Modify: `tests/BestSellersDataSemantics.Tests.ps1`
- Modify: `src/SellerIntelligence.psm1`
- Modify: `scripts/New-SellerIntelligenceReports.ps1`
- Modify: `tests/SellerIntelligence.Tests.ps1`
- Create: `web/lib/valid-market-days.ts`
- Create: `web/tests/valid-market-days.test.mjs`
- Modify: `web/lib/live-dashboard-data.ts`
- Modify: `web/tests/live-dashboard-data.test.mjs`

**Interfaces:**

- Consumes: Task 1 的 `Test-BestSellersExactTop30`；D1 `SnapshotRow`、`CategoryDayRow`、`ObservationRow`。
- Produces: PowerShell `Get-BestSellersValidHistory`、`Get-BestSellersPreviousValidSnapshot`；Seller Intelligence 的总览/类目有效基线；TypeScript `selectValidCategoryDays`、`previousValidMarketDate`。

- [ ] **Step 1：写 PowerShell 有效日失败测试**

```powershell
Describe 'V2 valid market days' {
    function New-Day($date, $complete=$true) {
        $rows = 1..30 | ForEach-Object { [pscustomobject]@{ rank=$_; asin=('B' + $_.ToString('000000000')); title='x'; price=$null; rating=$null; reviews=$null } }
        [pscustomobject]@{ market_date=$date; persisted_complete=$complete; pressure_washers=$rows }
    }

    It 'skips a failed day and returns the previous valid snapshot' {
        $history = @(New-Day '2026-08-18'; New-Day '2026-08-19' $false; New-Day '2026-08-20')
        $previous = Get-BestSellersPreviousValidSnapshot -Snapshots $history -CategoryKey pressure_washers -CurrentMarketDate '2026-08-20'
        $previous.market_date | Should Be '2026-08-18'
    }

    It 'keeps a ranking day valid when optional metrics are null' {
        $day = New-Day '2026-08-20'
        (Test-BestSellersExactTop30 -Items $day.pressure_washers) | Should Be $true
    }
}
```

- [ ] **Step 2：运行 PowerShell 测试并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1
```

Expected: FAIL，因为有效日函数尚不存在。

- [ ] **Step 3：实现 PowerShell 有效日函数**

在 `BestSellersDataSemantics.psm1` 中实现并导出：

```powershell
function Test-BestSellersExactTop30 { param([object[]]$Items) }
function Get-BestSellersValidHistory { param([object[]]$Snapshots,[string[]]$CategoryKeys) }
function Get-BestSellersPreviousValidSnapshot { param([object[]]$Snapshots,[string[]]$CategoryKeys,[string]$CurrentMarketDate) }
```

`Get-BestSellersValidHistory` 同时要求 `persisted_complete -eq $true`，并要求 `CategoryKeys` 中每个类目均为 Exact Top30；按 `market_date` 升序。单类目调用传一个 key，总览调用传当前 Market Context 的全部 raw category keys。`Get-BestSellersPreviousValidSnapshot` 只从早于 CurrentMarketDate 的有效历史中取最后一项。

把模块导出更新为：

```powershell
Export-ModuleMember -Function Get-BestSellersProductClassification, Get-BestSellersBrandNormalization, Test-BestSellersExactTop30, Get-BestSellersValidHistory, Get-BestSellersPreviousValidSnapshot
```

- [ ] **Step 4：运行 PowerShell 测试并确认 GREEN**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1
```

Expected: PASS。

- [ ] **Step 5：写 Seller Intelligence 语义收口失败测试**

在 `tests/SellerIntelligence.Tests.ps1` 的 `BeforeAll` 显式导入 `src/BestSellersDataSemantics.psm1`，再增加：

```powershell
It 'uses the shared exact Top 30 validator' {
    $complete = @(1..30 | ForEach-Object { [pscustomobject]@{ rank=$_; asin=('B' + $_.ToString('000000000')) } })
    (SellerIntelligence\Test-SellerExactTop30 -Items $complete) |
        Should Be (BestSellersDataSemantics\Test-BestSellersExactTop30 -Items $complete)
    (SellerIntelligence\Test-SellerExactTop30 -Items $complete[0..28]) |
        Should Be (BestSellersDataSemantics\Test-BestSellersExactTop30 -Items $complete[0..28])
}

It 'skips an invalid receipt between adjacent valid report days' {
    # 在 TestDrive 建立 2026-08-18、19、20 三个快照目录；复制真实 fixture，
    # 令 19 日 receipt 的 snapshot_sha256 与文件不一致，再以 20 日生成 Daily 报告。
    $result = & $newReportsScript -SnapshotPath $day20Snapshot -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive | ConvertFrom-Json
    $overview = Get-Content -LiteralPath (@($result.ReportPaths | Where-Object { [IO.Path]::GetFileName($_) -eq 'overview.json' })[0]) -Raw | ConvertFrom-Json
    @($overview.signals | Where-Object { $_.baselineDate -eq '2026-08-19' }).Count | Should Be 0
    @($overview.signals | Where-Object { $_.baselineDate -eq '2026-08-18' }).Count | Should BeGreaterThan 0
}

It 'rejects an explicit previous snapshot without a valid sibling receipt' {
    { & $newReportsScript -SnapshotPath $day20Snapshot -PreviousSnapshotPath $day19Snapshot -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive } |
        Should Throw 'Previous seller intelligence snapshot requires a valid capture receipt.'
}
```

Fixture 构造必须重新计算 18、20 日的合法 receipt；不得通过 mock 掉 `Test-BestSellersCaptureReceipt.ps1` 来掩盖真实回执边界。为便于断言基线，在生成的 rank-move / entry / exit signal 中加入 `baselineDate`，但不改变既有 signal kind 和优先级语义。

- [ ] **Step 6：运行 Seller Intelligence 测试并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\SellerIntelligence.Tests.ps1
```

Expected: FAIL，因为 Seller Intelligence 仍有独立 Exact Top30 实现、显式上一快照未校验回执，且 signal 尚未携带基线日期。

- [ ] **Step 7：让本地报告消费统一有效日选择器**

修改 `src/SellerIntelligence.psm1`：

- 在模块顶部导入 `BestSellersDataSemantics.psm1`；
- 保留公开的 `Test-SellerExactTop30` 兼容入口，但函数体只委托 `BestSellersDataSemantics\Test-BestSellersExactTop30`，删除第二套 rank/ASIN 完整性算法；
- `New-SellerIntelligenceReports` 新增可选 `PreviousSnapshotsByCategory` 参数；未提供时继续接受既有 `PreviousSnapshot`；
- overview 使用全部三个类目共同有效的上一快照，category report 优先使用对应 key 的上一有效快照；
- 所有比较型 signal 写入实际 `baselineDate`，让失败日跳过可审计。

修改 `scripts/New-SellerIntelligenceReports.ps1`：

- 只有 sibling receipt 经现有验证脚本确认有效后，才为加载的 snapshot 附加内存字段 `persisted_complete = $true`；不得改写原始 JSON；
- 自动选择时，对 overview 调用一次 `Get-BestSellersPreviousValidSnapshot`（全部三个类目），对每个 category 分别调用一次（单 category）；
- `historySnapshots` 仅包含回执有效的快照，完整日计数改为调用 `Get-BestSellersValidHistory`，不在脚本内重写完整性算法；
- `PreviousSnapshotPath` 存在时必须先校验同目录 receipt，再参与上述有效日选择；回执缺失或无效时明确失败；
- 当前快照仍需有效 receipt；当前类目若非 Exact Top30，不产生 Entry/Exit/Rank Comparison。

- [ ] **Step 8：运行本地报告测试并确认 GREEN**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1, .\tests\SellerIntelligence.Tests.ps1
```

Expected: PASS；08-19 不会成为任何报告的比较基线，08-18 会成为 08-20 的上一有效日。

- [ ] **Step 9：写 TypeScript 有效日失败测试**

`web/tests/valid-market-days.test.mjs`：

```js
import assert from "node:assert/strict";
import test from "node:test";
import { previousValidMarketDate, selectValidCategoryDays } from "../lib/valid-market-days.ts";

const rows = (date) => Array.from({ length: 30 }, (_, index) => ({ market_date: date, category_key: "pressure_washers", rank: index + 1, asin: `B${String(index + 1).padStart(9, "0")}` }));
const dates = ["2026-08-18", "2026-08-19", "2026-08-20"];
const categoryDays = dates.map((market_date) => ({ market_date, category_key: "pressure_washers", complete: market_date === "2026-08-19" ? 0 : 1 }));

test("selects the previous valid day across a failed snapshot", () => {
  const observations = dates.flatMap(rows);
  const valid = selectValidCategoryDays({ categoryKey: "pressure_washers", categoryDays, observations });
  assert.deepEqual(valid, ["2026-08-18", "2026-08-20"]);
  assert.equal(previousValidMarketDate(valid, "2026-08-20"), "2026-08-18");
});
```

- [ ] **Step 10：运行 TypeScript 测试并确认 RED**

Run from `web`:

```powershell
& "$nodeBin\node.exe" --test tests/valid-market-days.test.mjs
```

Expected: FAIL with module-not-found。

- [ ] **Step 11：实现 TypeScript 有效日选择器**

`web/lib/valid-market-days.ts` 导出：

```ts
export function selectValidCategoryDays(input: {
  categoryKey: CategoryKey;
  categoryDays: Array<Pick<CategoryDayRow, "market_date" | "category_key" | "complete">>;
  observations: Array<Pick<ObservationRow, "market_date" | "category_key" | "rank" | "asin">>;
}): string[];

export function previousValidMarketDate(validDates: string[], currentMarketDate: string): string | null;
```

内部对每个日期调用 `validateCategory` 所需的最小 Observation 适配器，并与 `complete === 1` 双重校验。输出去重、升序日期。

- [ ] **Step 12：修正网站 Dashboard Baseline**

修改 `web/lib/live-dashboard-data.ts`：

- 每个 Category 先用 `selectValidCategoryDays` 生成 history date；
- 当前日有效时，用 `previousValidMarketDate` 查找最近更早有效日；
- 删除 `immediatelyPreviousDate` 对 Category Comparison 的限制；
- Product History 只保留对应 Category Day 有效的 Observation；
- `previousComparableDate` 继续只在跨 Category 使用同一有效基线时返回日期。

把 `web/tests/live-dashboard-data.test.mjs` 中“does not skip an incomplete immediately preceding market day”改为“skips an incomplete day and compares with the previous valid market day”，断言 baseline 为 2026-08-18 且 comparison ready。

- [ ] **Step 13：运行 Valid Day、Seller Intelligence 与 Dashboard 测试并提交**

Run:

```powershell
Invoke-Pester -Script ..\tests\BestSellersDataSemantics.Tests.ps1, ..\tests\SellerIntelligence.Tests.ps1
& "$nodeBin\node.exe" --test tests/valid-market-days.test.mjs tests/live-dashboard-data.test.mjs tests/analytics.test.mjs
```

Expected: PASS。

Commit:

```powershell
git add src/BestSellersDataSemantics.psm1 tests/BestSellersDataSemantics.Tests.ps1 src/SellerIntelligence.psm1 scripts/New-SellerIntelligenceReports.ps1 tests/SellerIntelligence.Tests.ps1 web/lib/valid-market-days.ts web/tests/valid-market-days.test.mjs web/lib/live-dashboard-data.ts web/tests/live-dashboard-data.test.mjs
git commit -m "fix: unify valid market day selection"
```

---

### Task 4：PostgreSQL Product Metadata 与有效日查询

**Files:**

- Create: `db/migrations/012_best_sellers_product_metadata.sql`
- Modify: `src/BestSellersPostgres.psm1`
- Modify: `tests/AmazonIntelligence.Tests.ps1`
- Create: `tests/postgres/012_best_sellers_product_metadata.sql`

**Interfaces:**

- Consumes: Task 1 Classification/Brand result；Task 3 Exact Top30。
- Produces: `amazon_intelligence.best_sellers_product_metadata`、`best_sellers_valid_category_day`、`upsert_best_sellers_product_metadata(jsonb)`；更新后的 `New-BestSellersImportSql`。

- [ ] **Step 1：写 PostgreSQL Migration 失败测试**

在 `tests/AmazonIntelligence.Tests.ps1` 的 PostgreSQL migrations Describe 中加入：

```powershell
It 'defines the V2 product metadata dimension and valid market day view' {
    $migration = Get-Content (Join-Path $projectRoot 'db\migrations\012_best_sellers_product_metadata.sql') -Raw
    $migration | Should Match 'CREATE TABLE best_sellers_product_metadata'
    $migration | Should Match 'PRIMARY KEY \(marketplace_code, asin\)'
    $migration | Should Match 'CREATE VIEW best_sellers_valid_category_day'
    $migration | Should Match 'quality_passed'
    $migration | Should Match 'count\(DISTINCT o\.rank\) = 30'
    $migration | Should Match 'count\(DISTINCT o\.asin\) = 30'
    $migration | Should Match 'min\(o\.rank\) = 1'
    $migration | Should Match 'max\(o\.rank\) = 30'
    $migration | Should Match 'CREATE FUNCTION upsert_best_sellers_product_metadata'
}
```

在 Best Sellers PostgreSQL import Describe 中加入：

```powershell
It 'imports product metadata in the same transaction as the verified snapshot' {
    $sql = New-BestSellersImportSql -ArtifactPath $artifactPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -MetadataRows @(
        [pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000001'; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='product-rules-v1'; classification_evidence=@('NO_SAFE_RULE_MATCH'); raw_brand=$null; normalized_brand=$null; normalized_brand_key=$null; brand_alias_rule_id=$null; brand_source='unknown'; first_seen_market_date='2026-08-20'; last_seen_market_date='2026-08-20' }
    )
    $sql | Should Match 'BEGIN;'
    $sql | Should Match 'ingest_best_sellers_snapshot'
    $sql | Should Match 'upsert_best_sellers_product_metadata'
    $sql | Should Match 'COMMIT;'
}
```

- [ ] **Step 2：运行目标 Pester 并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\AmazonIntelligence.Tests.ps1
```

Expected: FAIL，因为 migration 和 MetadataRows 参数尚不存在。

- [ ] **Step 3：编写 PostgreSQL Migration**

`012_best_sellers_product_metadata.sql` 必须包含：

```sql
BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE best_sellers_product_metadata (
    marketplace_code varchar(32) NOT NULL,
    asin char(10) NOT NULL CHECK (asin ~ '^[A-Z0-9]{10}$'),
    product_type varchar(64) NOT NULL,
    classification_confidence varchar(16) NOT NULL CHECK (classification_confidence IN ('high','medium','low')),
    classification_rule_id varchar(120),
    classification_rule_version varchar(80) NOT NULL,
    classification_evidence jsonb NOT NULL CHECK (jsonb_typeof(classification_evidence) = 'array'),
    raw_brand varchar(300),
    normalized_brand varchar(300),
    normalized_brand_key varchar(300),
    brand_alias_rule_id varchar(120),
    brand_source varchar(32) NOT NULL CHECK (brand_source IN ('verified_metadata','manual_review','unknown')),
    first_seen_market_date date NOT NULL,
    last_seen_market_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (marketplace_code, asin),
    CHECK (first_seen_market_date <= last_seen_market_date),
    CHECK ((product_type = 'unknown' AND classification_confidence = 'low') OR product_type <> 'unknown'),
    CHECK ((brand_source = 'unknown' AND raw_brand IS NULL AND normalized_brand IS NULL AND normalized_brand_key IS NULL) OR (brand_source <> 'unknown' AND raw_brand IS NOT NULL AND normalized_brand IS NOT NULL AND normalized_brand_key IS NOT NULL))
);
```

Valid Day View 从最新 `best_sellers_source_run` 版本出发，只输出 `quality_passed=true` 且 item、unique ASIN、unique rank 和实际 rank 1–30 均满足 30 的 Category Date。

`upsert_best_sellers_product_metadata(jsonb)`：

- 遍历 JSON Array；
- First Seen 使用 `LEAST(existing, excluded)`；
- Last Seen 使用 `GREATEST(existing, excluded)`；
- Unknown Brand 不覆盖 Verified Brand；
- 非 Unknown 的高置信分类可覆盖 Unknown；
- 更新 `updated_at`；
- 返回 upsert row count。

`best_sellers_valid_category_day` 除了 `count(DISTINCT rank)=30`，还必须要求 `min(rank)=1`、`max(rank)=30`，避免 2–31 这类错误区间被误判为完整。

- [ ] **Step 4：扩展 Snapshot Import SQL**

修改 `New-BestSellersImportSql` 签名：

```powershell
function New-BestSellersImportSql {
    param(
        [Parameter(Mandatory=$true)][string]$ArtifactPath,
        [Parameter(Mandatory=$true)][string]$SourceConfigPath,
        [object[]]$MetadataRows = @()
    )
}
```

输出单一事务：先调用 `ingest_best_sellers_snapshot`，再将 `$MetadataRows` JSON 调用 `upsert_best_sellers_product_metadata`，最后 COMMIT。沿用现有 PostgreSQL literal escaping，不在 SQL 或日志中加入凭证。

同时给 `Invoke-BestSellersPostgresImport` 增加 `[object[]]$MetadataRows=@()` 参数，并原样传给 `New-BestSellersImportSql`；旧调用者不传参数时继续只导入 Snapshot。

- [ ] **Step 5：运行 Migration/Import 测试并确认 GREEN**

Run:

```powershell
Invoke-Pester -Script .\tests\AmazonIntelligence.Tests.ps1
```

Expected: PASS。

- [ ] **Step 6：提交 PostgreSQL Task**

```powershell
git add db/migrations/012_best_sellers_product_metadata.sql src/BestSellersPostgres.psm1 tests/AmazonIntelligence.Tests.ps1 tests/postgres/012_best_sellers_product_metadata.sql
git commit -m "feat: store best sellers product metadata"
```

只添加实际存在的 test migration copy；如果测试直接读取主 migration，不创建或暂存重复文件。

---

### Task 5：D1 Schema、Store 与幂等迁移

**Files:**

- Modify: `web/db/schema.ts`
- Create: `web/drizzle/0003_product_metadata.sql`（由 Drizzle `--name product_metadata` 生成）
- Create: `web/drizzle/meta/0003_snapshot.json`
- Modify: `web/drizzle/meta/_journal.json`
- Modify: `web/lib/d1.ts`
- Modify: `web/lib/dashboard-store.ts`
- Modify: `web/tests/migration-integrity.test.mjs`
- Modify: `web/tests/live-dashboard-data.test.mjs`

**Interfaces:**

- Consumes: Task 2 `ProductMetadata` 类型。
- Produces: D1 `product_metadata` table；`DashboardStore.listProductMetadata()` 和 `listProductMetadataByAsins(asins)`。

- [ ] **Step 1：写 D1 Migration 失败测试**

在 `web/tests/migration-integrity.test.mjs` 加入：

```js
test("applies the product metadata migration twice over the current schema", () => {
  const database = new DatabaseSync(":memory:");
  database.exec("CREATE TABLE observations (market_date TEXT NOT NULL, category_key TEXT NOT NULL, rank INTEGER NOT NULL, asin TEXT NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, price REAL, rating REAL, reviews INTEGER, PRIMARY KEY (market_date, category_key, rank))");
  const migration = readFileSync(`${drizzleDirectory}0003_product_metadata.sql`, "utf8");
  const statements = migration.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean);
  for (const statement of statements) database.exec(statement);
  for (const statement of statements) database.exec(statement);
  const table = database.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND name='product_metadata'").get();
  assert.equal(table.name, "product_metadata");
  database.close();
});
```

在 `live-dashboard-data.test.mjs` 的 fake store 增加失败断言：

```js
assert.equal((await store.listProductMetadata()).length, 1);
```

- [ ] **Step 2：运行 Migration Test 并确认 RED**

Run from `web`:

```powershell
& "$nodeBin\node.exe" --test tests/migration-integrity.test.mjs
```

Expected: FAIL，因为 `0003_product_metadata.sql` 不存在。

- [ ] **Step 3：新增 D1 Schema 与 Migration**

在 `web/db/schema.ts` 新增 `productMetadata`，列名与 `ProductMetadata` 一一对应；`classification_evidence_json` 保存 JSON Text；主键 `(marketplace, asin)`；增加 `normalized_brand_key` 和 `product_type` 索引。

`0003_product_metadata.sql` 使用：

```sql
CREATE TABLE IF NOT EXISTS `product_metadata` (...);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_product_metadata_type` ON `product_metadata` (`product_type`);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_product_metadata_brand` ON `product_metadata` (`normalized_brand_key`);
```

运行 Drizzle 生成命令产生 snapshot/journal，而不是手写 snapshot：

```powershell
$env:Path=$nodeBin+';'+$env:Path
& 'C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd' db:generate -- --name product_metadata
```

确认生成结果恰好包含 `0003_product_metadata.sql`、`meta/0003_snapshot.json`，且 Journal Tag 为 `0003_product_metadata`；若不是，先检查命令参数和当前 Journal 序号，不手工伪造 Snapshot。

- [ ] **Step 4：更新 Runtime Schema Compatibility**

在 `web/lib/d1.ts` 的 `ensureSchema` 追加与 migration 等价的 `CREATE TABLE/INDEX IF NOT EXISTS`，不改变旧表 SQL。

- [ ] **Step 5：扩展 Dashboard Store**

在 `web/lib/dashboard-store.ts` 添加：

```ts
export type ProductMetadataRow = ProductMetadata;

export interface DashboardStore {
  // existing methods remain
  listProductMetadata(): Promise<ProductMetadataRow[]>;
  listProductMetadataByAsins(asins: string[]): Promise<ProductMetadataRow[]>;
}
```

`listProductMetadataByAsins` 对空数组直接返回 `[]`；非空数组构造固定数量的 `?` placeholder 并通过 `.bind(...asins)` 参数化查询。解析 `classification_evidence_json` 时，非法 JSON 返回空 Evidence 并由上层 Contract 视为无效 Metadata，不抛出内部详情。

- [ ] **Step 6：运行 D1 Tests 并提交**

Run:

```powershell
& "$nodeBin\node.exe" --test tests/migration-integrity.test.mjs tests/live-dashboard-data.test.mjs
```

Expected: PASS。

Commit:

```powershell
git add web/db/schema.ts web/drizzle web/lib/d1.ts web/lib/dashboard-store.ts web/tests/migration-integrity.test.mjs web/tests/live-dashboard-data.test.mjs
git commit -m "feat: add d1 product metadata dimension"
```

---

### Task 6：Dashboard Sync Bundle v2 与原子写入

**Files:**

- Modify: `scripts/New-DashboardSyncBundle.ps1`
- Modify: `src/DashboardSyncBundle.psm1`
- Modify: `tests/DashboardSyncBundle.Tests.ps1`
- Modify: `web/lib/sync-contract.ts`
- Modify: `web/app/api/sync/v1/bundles/route.ts`
- Modify: `web/tests/sync-contract.test.mjs`
- Modify: `web/tests/sync-bundle-route.test.mjs`

**Interfaces:**

- Consumes: Task 1 PowerShell semantics；Task 4 Metadata SQL shape；Task 5 D1 table。
- Produces: `amazon-bs-dashboard-bundle-v2`；经过验证的 `productMetadata`；同一 D1 batch 中的 metadata delete/upsert。

- [ ] **Step 1：写 PowerShell Bundle v2 失败测试**

在 `tests/DashboardSyncBundle.Tests.ps1` 加入：

```powershell
It 'builds a v2 bundle with one metadata row per snapshot ASIN' {
    $result = & $bundleScript -SnapshotPath $snapshotPath | ConvertFrom-Json
    $bundle = Get-Content -LiteralPath $result.BundlePath -Raw | ConvertFrom-Json
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    $expectedAsins = @($snapshot.pressure_washers + $snapshot.sump_pumps + $snapshot.pressure_washer_accessories | ForEach-Object { [string]$_.asin } | Sort-Object -Unique)
    $bundle.schemaVersion | Should Be 'amazon-bs-dashboard-bundle-v2'
    @($bundle.productMetadata).Count | Should Be $expectedAsins.Count
    @($bundle.productMetadata | Select-Object -ExpandProperty asin -Unique).Count | Should Be $expectedAsins.Count
    @($bundle.productMetadata | Where-Object { $_.brandSource -eq 'unknown' -and $null -eq $_.rawBrand }).Count | Should BeGreaterThan 0
}
```

- [ ] **Step 2：运行 Bundle Test 并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\DashboardSyncBundle.Tests.ps1
```

Expected: FAIL，因为当前 Bundle 是 v1 且没有 Product Metadata。

- [ ] **Step 3：生成 Metadata Cohort**

修改 `DashboardSyncBundle.psm1`：

- 导入 `BestSellersDataSemantics.psm1`；
- 对 Snapshot 三个 Category 的 ASIN 去重；
- 同一 ASIN 多 Category 时保留一个 Metadata Row，分类优先使用 `pressure_washers`，再使用 `pressure_washer_accessories`，最后 `sump_pumps`；
- 调用 Product Classifier；
- 当前 Snapshot 没有 Verified Brand 字段时生成 Unknown Brand；
- `firstSeenMarketDate` 和 `lastSeenMarketDate` 在仅有当前 Snapshot 时都等于 MarketDate；D1 upsert 后续通过历史 bundle 使用 MIN/MAX 合并；
- 输出 v2 schema 和 90 个 Metadata Row。

- [ ] **Step 4：运行 PowerShell Bundle Test 并确认 GREEN**

Run:

```powershell
Invoke-Pester -Script .\tests\DashboardSyncBundle.Tests.ps1
```

Expected: PASS。

- [ ] **Step 5：写 TypeScript Contract 失败测试**

在 `web/tests/sync-contract.test.mjs` 加入：

```js
const validBundleV1 = () => ({
  schemaVersion: "amazon-bs-dashboard-bundle-v1",
  marketDate: "2026-08-12",
  observedAt: "2026-08-12T00:00:00Z",
  receiptSha256: "a".repeat(64),
  categories: [{ key: "pressure_washers", sourceUrl: "https://www.amazon.com/zgbs/552856", observations }],
  reports: [],
});

const validBundleV2 = () => {
  const base = validBundleV1();
  return {
    ...base,
    schemaVersion: "amazon-bs-dashboard-bundle-v2",
    productMetadata: observations.map(({ asin }) => ({
      marketplace: "AMAZON_US",
      asin,
      productType: "unknown",
      classificationConfidence: "low",
      classificationRuleId: null,
      classificationRuleVersion: "product-rules-v1",
      classificationEvidence: ["NO_SAFE_RULE_MATCH"],
      rawBrand: null,
      normalizedBrand: null,
      normalizedBrandKey: null,
      brandAliasRuleId: null,
      brandSource: "unknown",
      firstSeenMarketDate: "2026-08-12",
      lastSeenMarketDate: "2026-08-12",
    })),
  };
};

test("accepts a v2 bundle with one coherent product metadata cohort", () => {
  const bundle = validBundleV2();
  const result = validateSyncBundle(bundle);
  assert.equal(result.ok, true);
  assert.equal(result.productMetadata.length, 90);
});

test("rejects unknown high and normalized brand without verified raw brand", () => {
  const bundle = validBundleV2();
  bundle.productMetadata[0] = { ...bundle.productMetadata[0], productType: "unknown", classificationConfidence: "high" };
  assert.equal(validateSyncBundle(bundle).ok, false);
  bundle.productMetadata[0] = { ...validBundleV2().productMetadata[0], rawBrand: null, normalizedBrand: "Invented", normalizedBrandKey: "invented", brandSource: "unknown" };
  assert.equal(validateSyncBundle(bundle).ok, false);
});

test("keeps v1 bundles readable with an empty metadata cohort", () => {
  const result = validateSyncBundle(validBundleV1());
  assert.equal(result.ok, true);
  assert.deepEqual(result.productMetadata, []);
});
```

- [ ] **Step 6：运行 Contract Test 并确认 RED**

Run from `web`:

```powershell
& "$nodeBin\node.exe" --test tests/sync-contract.test.mjs
```

Expected: FAIL，因为 v2 schema 和 productMetadata 尚未验证。

- [ ] **Step 7：实现 Sync Contract v1/v2 Union**

修改 `validateSyncBundle`：

- 明确接受 `amazon-bs-dashboard-bundle-v1` 和 `amazon-bs-dashboard-bundle-v2`；
- v1 返回 `productMetadata: []`；
- v2 要求 Metadata ASIN Set 与 categories observations 的唯一 ASIN Set 完全相等；
- 验证 Product Type、Confidence、Brand Source、日期和 Evidence；
- Unknown Type 只允许 Low；
- Unknown Brand 的全部 Brand 字段必须 null；
- First Seen <= Last Seen；
- 不允许重复 Marketplace + ASIN。

- [ ] **Step 8：写并实现 D1 原子写入测试**

在 `sync-bundle-route.test.mjs` 新增 `completeBundleV2()`，由现有 `completeBundle()` 的全部唯一 ASIN 生成与上一 Step 相同字段的 Unknown Metadata。把 `sameReceiptEnvironment()` 扩展为收集每次 `DB.batch()` 的完整 statement array，然后先加入失败测试：

```js
test("writes snapshot observations discounts and product metadata in one batch", async () => {
  const env = sameReceiptEnvironment();
  const response = await request(completeBundleV2(), env);
  assert.equal(response.status, 201);
  assert.equal(env.batches.length, 1);
  assert.ok(env.batches[0].some((statement) => /^INSERT INTO product_metadata/i.test(statement.sql)));
});
```

确认 RED 后修改 route：

- v2 batch 添加 `INSERT ... ON CONFLICT(marketplace, asin) DO UPDATE`；
- First Seen 使用较小日期，Last Seen 使用较大日期；
- Incoming Unknown Brand 不覆盖 existing Verified Brand，使用 SQL CASE；
- batch 失败时不暴露任何新 Snapshot/Metadata；
- v1 保持原有写入行为。

- [ ] **Step 9：运行 Sync Tests 并提交**

Run:

```powershell
& "$nodeBin\node.exe" --test tests/sync-contract.test.mjs tests/sync-bundle-route.test.mjs tests/migration-integrity.test.mjs
```

Expected: PASS。

Commit:

```powershell
git add scripts/New-DashboardSyncBundle.ps1 src/DashboardSyncBundle.psm1 tests/DashboardSyncBundle.Tests.ps1 web/lib/sync-contract.ts web/app/api/sync/v1/bundles/route.ts web/tests/sync-contract.test.mjs web/tests/sync-bundle-route.test.mjs
git commit -m "feat: sync v2 product metadata"
```

---

### Task 7：本地 Snapshot Import 集成与历史 First/Last Seen

**Files:**

- Modify: `scripts/Import-VerifiedBestSellersSnapshot.ps1`
- Modify: `src/BestSellersPostgres.psm1`
- Modify: `tests/AmazonIntelligence.Tests.ps1`
- Modify: `tests/BestSellersDataSemantics.Tests.ps1`

**Interfaces:**

- Consumes: Task 1 Classifier/Brand Normalizer；Task 4 `New-BestSellersImportSql -MetadataRows`。
- Produces: `New-BestSellersProductMetadataRows`；每次 Verified Snapshot Import 同事务更新 Metadata。

- [ ] **Step 1：写 Metadata Row 失败测试**

```powershell
It 'deduplicates ASINs and keeps first and last seen dates from verified history' {
    $rows = New-BestSellersProductMetadataRows -Snapshots @($day18,$day20) -MarketplaceCode AMAZON_US -ClassificationConfigPath $classificationPath -BrandAliasConfigPath $brandPath
    $product = @($rows | Where-Object asin -eq 'B000000001')
    $product.Count | Should Be 1
    $product[0].first_seen_market_date | Should Be '2026-08-18'
    $product[0].last_seen_market_date | Should Be '2026-08-20'
    $product[0].brand_source | Should Be 'unknown'
}
```

在 import test 中断言 Script 将 MetadataRows 传给 `New-BestSellersImportSql`，且只有 Receipt Valid 时才生成。

- [ ] **Step 2：运行测试并确认 RED**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1,.\tests\AmazonIntelligence.Tests.ps1
```

Expected: FAIL，因为 Metadata Row builder 和 Import integration 尚不存在。

- [ ] **Step 3：实现 Metadata Row Builder**

在 `BestSellersDataSemantics.psm1` 新增：

```powershell
function New-BestSellersProductMetadataRows {
    param(
        [Parameter(Mandatory=$true)][object[]]$Snapshots,
        [Parameter(Mandatory=$true)][ValidateSet('AMAZON_US')][string]$MarketplaceCode,
        [Parameter(Mandatory=$true)][string]$ClassificationConfigPath,
        [Parameter(Mandatory=$true)][string]$BrandAliasConfigPath
    )
}
```

只处理 `persisted_complete=true` 且 Exact Top30 的 Category Day；按 ASIN 聚合 first/last date；分类使用最新有效 Title 和固定 Category 优先级；Brand 无 Verified Field 时调用 Unknown 分支。

- [ ] **Step 4：集成 Verified Snapshot Import**

在 `Import-VerifiedBestSellersSnapshot.ps1`：

1. 保持现有 Receipt 验证在最前；
2. 读取当前 Snapshot；
3. 包装为 `persisted_complete=true` 的 Metadata 输入；
4. 调用 `New-BestSellersProductMetadataRows`；
5. 将结果传入 `Invoke-BestSellersPostgresImport -MetadataRows $metadataRows`；
6. 继续使用一次 psql transaction；
7. 返回结果增加 `MetadataCount`，不改变既有 `Status`。

- [ ] **Step 5：运行 Import Tests 并提交**

Run:

```powershell
Invoke-Pester -Script .\tests\BestSellersDataSemantics.Tests.ps1,.\tests\AmazonIntelligence.Tests.ps1
```

Expected: PASS。

Commit:

```powershell
git add src/BestSellersDataSemantics.psm1 scripts/Import-VerifiedBestSellersSnapshot.ps1 src/BestSellersPostgres.psm1 tests/BestSellersDataSemantics.Tests.ps1 tests/AmazonIntelligence.Tests.ps1
git commit -m "feat: import verified product metadata"
```

---

### Task 8：Public API 语义、Raw/Analytical 分离与 Methodology

**Files:**

- Modify: `web/app/api/public/rankings/route.ts`
- Modify: `web/app/api/public/overview/route.ts`
- Modify: `web/lib/live-dashboard-data.ts`
- Modify: `web/app/methodology/page.tsx`
- Modify: `web/tests/public-data-routes.test.mjs`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**

- Consumes: Task 2 Market Context；Task 3 Valid Market Day；Task 5 Product Metadata Store。
- Produces: Raw Ranking 不过滤保证；Overview 的独立 `marketContext` 与 `analyticalObservations` 数据；准确 Methodology 文案。

- [ ] **Step 1：写 Raw/Analytical 分离失败测试**

在 `public-data-routes.test.mjs` 加入：

```js
test("raw rankings keep all Top 30 rows when an analytical segment is requested", async () => {
  const response = await rankingsGET(new Request("https://example.test/api/public/rankings?marketplace=US&category=pressure_washers&segment=machines"));
  const body = await response.json();
  assert.equal(body.observations.length, 30);
  assert.equal(body.scope, "raw_ranking");
});

test("overview returns a separately filtered analytical market", async () => {
  const response = await overviewGET(new Request("https://example.test/api/public/overview?marketplace=US&category=pressure_washers&segment=machines"));
  const body = await response.json();
  assert.equal(body.marketContext.segment, "machines");
  assert.ok(body.analyticalObservations.every((row) => ["electric_pressure_washer","gas_pressure_washer","cordless_pressure_washer"].includes(row.productType)));
});
```

- [ ] **Step 2：运行 Public Route Tests 并确认 RED**

Run from `web`:

```powershell
& "$nodeBin\node.exe" --test tests/public-data-routes.test.mjs
```

Expected: FAIL，因为 scope、Market Context 和 Analytical Observations 尚不存在。

- [ ] **Step 3：实现 API 语义**

- Rankings Route 解析并验证 Market Context，但始终返回完整 Raw Category observations，增加 `scope: "raw_ranking"`；
- Overview Route 接受 Request，调用 `parseMarketContext`，从 Store 读取 Metadata，调用 `filterAnalyticalMarket`，返回 `marketContext`、Raw count 和 Analytical observations；
- Metadata 缺失的 ASIN 在 `all_bestsellers` 可见，在具体 Segment 中排除；
- 不支持 Context 返回 HTTP 400 `{ error: "unsupported_market_context" }`；
- 不把 D1 故障隐藏为新的 V2 Analytical 结论。Legacy 页面 Seed Fallback 保持现状，直到 V2 Overview 页面替换时再移除。

- [ ] **Step 4：更新 Methodology 与 Render Test**

`web/app/methodology/page.tsx` 增加中文说明：

- Raw Ranking 与 Analytical Market 的区别；
- Brand Unknown 原则；
- 上一有效市场日会跳过失败/不完整日；
- Optional Field 缺失不影响 Rank Day Validity；
- “首次发现”不是“新品”。

在 `rendered-html.test.mjs` 断言这些核心文案可达且不包含 “Market Share/销量增长/新品” 等误导表述。

- [ ] **Step 5：运行 Public/Render Tests 并提交**

Run:

```powershell
& "$nodeBin\node.exe" --test tests/public-data-routes.test.mjs tests/rendered-html.test.mjs tests/market-context.test.mjs tests/valid-market-days.test.mjs
```

Expected: PASS。

Commit:

```powershell
git add web/app/api/public/rankings/route.ts web/app/api/public/overview/route.ts web/lib/live-dashboard-data.ts web/app/methodology/page.tsx web/tests/public-data-routes.test.mjs web/tests/rendered-html.test.mjs
git commit -m "feat: expose raw and analytical market semantics"
```

---

### Task 9：Phase 1 全量验证与停止点

**Files:**

- Modify only if verification finds a Phase 1 regression: the smallest directly responsible Phase 1 file and its failing test.
- Review: `docs/superpowers/specs/2026-08-27-v2-phase1-data-semantics-design.md`
- Review: `docs/audits/V2-PHASE-0-AUDIT-2026-08-27.md`

**Interfaces:**

- Consumes: Task 1–8 的全部交付。
- Produces: 可审核的 Phase 1 验证结果；不进入 Phase 2。

- [ ] **Step 1：运行 PowerShell 全量测试**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

Expected: `Failed: 0`，新增 Data Semantics 测试包含在总数中。

- [ ] **Step 2：运行 Python Collector 回归测试**

```powershell
& '.\.venv\Scripts\python.exe' -m unittest discover -s tests\python -p 'test_*.py'
```

Expected: `OK`。Crawler 未修改，80 个既有测试和任何新增测试均通过。

- [ ] **Step 3：运行网站全量测试与生产构建**

```powershell
$nodeBin='C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
$env:Path=$nodeBin+';'+$env:Path
& 'C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd' test
```

Expected: Node tests 0 fail，vinext build complete。

- [ ] **Step 4：运行 Lint**

```powershell
& 'C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd' lint
```

Expected: exit code 0，无 ESLint error。

- [ ] **Step 5：执行验收矩阵核对**

逐项用测试或只读查询确认：

```text
[ ] Raw Ranking 仍返回完整 Top30
[ ] Machines 不含 Accessory 或 Unknown
[ ] Brand 不从 Title 推断
[ ] Unknown Brand 字段均为 null
[ ] PostgreSQL/D1 均以 Marketplace + ASIN 唯一
[ ] 08-18 -> 08-20 是相邻有效日
[ ] 不完整日不产生比较结果
[ ] v1 Sync Bundle 继续可读
[ ] v2 Metadata Cohort 原子写入
[ ] 未新增 Phase 2 指标或 V2 业务页面
```

- [ ] **Step 6：检查工作树与提交验证修复**

```powershell
git status --short
git diff --check
git log --oneline -10
```

如果 Step 1–5 发现回归，必须先添加能复现问题的失败测试，再修复并重跑相关全量验证。通过 `git diff --name-only` 核对后，只暂存该失败测试及其直接修复文件，并使用提交信息 `fix: close phase 1 verification gap`；禁止使用 `git add .` 或暂存 `AGENTS.md`、Audit Report 等无关文件。

若没有回归，不创建空提交。

- [ ] **Step 7：停止并提交 Phase 1 评审结果**

最终报告只包含：

- 实际实现的语义与迁移；
- 每个验证命令的最新通过/失败数字；
- 保留的 Unknown Brand 数量和 Classification 分布；
- 已知限制；
- Phase 1 相关 commit；
- 明确声明“未进入 Phase 2”。

等待人工确认后才允许开始 Phase 2。
