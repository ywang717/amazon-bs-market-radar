# V2 Trusted Brand Evidence and Historical Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不篡改历史榜单快照、不降低 Top 30 抓取成功率的前提下，从 Amazon 商品详情页采集可信品牌证据，为未来每日抓取自动补充品牌，并对历史 131 个 ASIN 做一次可审计回填。

**Architecture:** 将品牌提取拆成纯判定器、详情页 DOM 适配器、历史回填采集器和发布入口四层。日常抓取复用现有折扣核验的详情页访问；历史回填生成独立 artifact 与 receipt，再分别通过元数据专用 PostgreSQL 导入和 D1 API 更新产品元数据。历史 ranking snapshot 与 receipt 全程只读。

**Tech Stack:** Python 3、Playwright、PowerShell 7/Pester、PostgreSQL、Next.js/TypeScript、Cloudflare D1、Vitest、OpenAI Sites。

**Spec:** `docs/superpowers/specs/2026-08-28-v2-brand-evidence-and-backfill-design.md`

## Global Constraints

- 只接受明确标注为 `Brand` 的商品概览、商品详情表或详情项目符号；首版禁止从标题、店铺 byline、推荐卡片或图片文字推断品牌。
- 品牌证据必须与请求 ASIN 一致；ASIN 不一致、页面阻断、来源冲突或字段缺失均返回 unknown。
- 品牌采集失败不得使 Top 30 榜单失败，也不得触发第二次商品详情页导航。
- `Get-BestSellersBrandNormalization` 仍是品牌规范化唯一权威；Python 只输出原始值、来源和核验状态。
- 历史回填只能写入 `var/brand-enrichment/<date>/` 和产品元数据存储，不得改写任何历史 snapshot 或 capture receipt。
- D1 更新必须经过独立鉴权端点、完整请求校验、冲突预检和一次原子 batch；不得混入榜单或快照 SQL。
- 每项实现遵循红—绿—重构：先运行目标测试并确认因预期缺失而失败，再写最小实现，再运行目标测试和相关回归测试。

---

## Task 1: 建立纯 Python 品牌证据判定器与 DOM 提取层

**Files:**

- Create: `scripts/python/brand_evidence.py`
- Modify: `scripts/python/collect_best_sellers.py`
- Create: `tests/python/test_brand_evidence.py`
- Modify: `tests/python/test_collect_best_sellers.py`

- [ ] **Step 1: 为纯判定器写失败测试**

在 `tests/python/test_brand_evidence.py` 覆盖以下输入与结果：

- 匹配 ASIN 且只有一个明确 Brand 值时，返回 `VERIFIED`、原始品牌、可信来源。
- 同一页面多个可信来源值一致时仍为 `VERIFIED`。
- 多个可信来源值冲突时返回 `CONFLICT`，不输出可写入品牌。
- 详情页 ASIN 与请求 ASIN 不一致时返回 `IDENTITY_MISMATCH`。
- 页面阻断、Brand 缺失或空值时分别返回 `VERIFICATION_BLOCKED` 或 `MISSING`。

核心接口固定为：

```python
def classify_brand_evidence(detail_page: dict, requested_asin: str) -> dict:
    # keys: raw_brand, brand_source, verification_status, evidence_source
    ...
```

运行：

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_brand_evidence -v
```

预期：因模块或接口尚不存在而失败。

- [ ] **Step 2: 实现最小纯判定器**

在 `brand_evidence.py` 中定义可信来源常量，仅允许：

```python
TRUSTED_BRAND_SOURCES = (
    "PRODUCT_OVERVIEW_BRAND_FIELD",
    "PRODUCT_DETAILS_BRAND_FIELD",
    "DETAIL_BULLET_BRAND_FIELD",
)
```

实现 ASIN 规范化、空白清理、大小写不敏感冲突比较和保守状态输出。不要在此层进行品牌别名规范化。

- [ ] **Step 3: 为 DOM 提取写失败测试**

在 `test_collect_best_sellers.py` 使用最小假页面对象验证：

- 从商品概览的精确 `Brand` 行提取候选值。
- 从商品详情表的精确 `Brand` 行提取候选值。
- 从显式 `Brand: value` 详情项目符号提取候选值。
- 忽略 `#bylineInfo`、标题、推荐商品卡片和不精确标签。
- 提取结果保留详情页 ASIN、阻断标记和各候选来源。

运行：

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_collect_best_sellers -v
```

预期：新断言失败，且失败只指向尚未实现的品牌证据字段。

- [ ] **Step 4: 在现有详情页提取函数中加入结构化候选值**

扩展 `_extract_detail_page` 的返回对象，加入：

```python
{
    "brand_candidates": [
        {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "..."},
        {"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": "..."},
        {"evidence_source": "DETAIL_BULLET_BRAND_FIELD", "value": "..."},
    ]
}
```

选择器只负责结构化读取；最终可信性由 `classify_brand_evidence` 统一判断。

- [ ] **Step 5: 运行 Python 目标测试并提交**

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_brand_evidence tests.python.test_collect_best_sellers -v
git add scripts/python/brand_evidence.py scripts/python/collect_best_sellers.py tests/python/test_brand_evidence.py tests/python/test_collect_best_sellers.py
git commit -m "feat: extract trusted Amazon brand evidence"
```

---

## Task 2: 在每日抓取中复用品牌证据且保持榜单容错

**Files:**

- Modify: `scripts/python/collect_best_sellers.py`
- Modify: `tests/python/test_collect_best_sellers.py`
- Modify: `tests/python/test_collect_best_sellers_recovery.py`
- Modify: `tests/fixtures/verified-best-sellers-snapshot.json`（仅当现有 fixture 生成器要求；不得修改历史生产快照）

- [ ] **Step 1: 写失败测试锁定“同一次访问”行为**

测试 `verify_chart_discounts` 对每个 observation 只调用一次 `page.goto`，同时返回折扣证据和品牌证据；品牌解析异常时折扣结果与 observation 仍成功。

目标返回值固定为：

```python
chart_results, discount_evidence, brand_evidence = await verify_chart_discounts(...)
```

运行：

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_collect_best_sellers -v
```

预期：旧函数只有两个返回值或 observation 未携带品牌字段而失败。

- [ ] **Step 2: 将纯判定器接入现有详情页循环**

在每次折扣详情核验完成后调用 `classify_brand_evidence`，并把结果按 ASIN 记录到 `brand_evidence`。仅在状态为 `verified` 时把 `raw_brand` 与 `brand_source` 附加到对应 observation；其他状态保留在诊断证据中。

- [ ] **Step 3: 保持恢复路径和成功门槛不变**

将 `brand_evidence` 贯穿 attempt diagnostic、恢复结果和序列化输出，但不把品牌覆盖率加入 Top 30 成功门槛。为品牌提取抛错增加局部捕获，输出 unknown 诊断，不中止当前类目。

- [ ] **Step 4: 运行恢复与完整 Python 测试并提交**

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_collect_best_sellers tests.python.test_collect_best_sellers_recovery -v
.\.venv\Scripts\python.exe -m unittest discover -s tests/python -p "test_*.py" -v
git add scripts/python/collect_best_sellers.py tests/python/test_collect_best_sellers.py tests/python/test_collect_best_sellers_recovery.py
git commit -m "feat: enrich daily capture with trusted brands"
```

---

## Task 3: 建立 PowerShell 回填 artifact、receipt、元数据合并和 PostgreSQL 专用导入

**Files:**

- Create: `src/BestSellersBrandEnrichment.psm1`
- Create: `tests/BestSellersBrandEnrichment.Tests.ps1`
- Modify: `src/BestSellersPostgres.psm1`
- Modify: `tests/BestSellersPostgres.Tests.ps1`

- [ ] **Step 1: 为 artifact 与 receipt 合同写失败测试**

在 Pester 中固定 artifact 的必填字段：

```text
schema_version = amazon-brand-enrichment-v1
marketplace = AMAZON_US
generated_at = 可解析的 ISO 时间戳
products = 每个请求 ASIN 恰好一条且按 ASIN 排序的结果
```

每条 product 包含 `asin`、`detail_url`、`verification_status`、`raw_brand`、`brand_source`、`evidence_source`。receipt 必须绑定 artifact SHA-256、排序后的 ASIN 集合哈希、记录数、VERIFIED/MISSING/CONFLICT/IDENTITY_MISMATCH/VERIFICATION_BLOCKED 计数和生成时间。

运行：

```powershell
Invoke-Pester .\tests\BestSellersBrandEnrichment.Tests.ps1 -Output Detailed
```

预期：模块不存在或函数缺失而失败。

- [ ] **Step 2: 实现 artifact 校验、哈希和 receipt 函数**

在新模块中实现并导出：

```powershell
Get-BestSellersVerifiedHistoryAsins
Get-BestSellersBrandAsinSetHash
Test-BestSellersBrandEnrichmentArtifact
New-BestSellersBrandEnrichmentReceipt
Test-BestSellersBrandEnrichmentReceipt
Merge-BestSellersBrandEnrichmentMetadata
```

ASIN 集合哈希算法固定为：去重、序数排序、使用 LF (`"`n") 连接后，以 UTF-8 无 BOM 计算 SHA-256。artifact 哈希针对磁盘上的精确 UTF-8 字节。

- [ ] **Step 3: 为元数据合并规则写失败测试**

覆盖：

- 只有 `VERIFIED` 结果能转成 `raw_brand` 与 `brand_source = verified_metadata`。
- 继续调用 `New-BestSellersProductMetadataRows`，由现有规范化表生成 `normalized_brand`。
- 已有 verified/manual 品牌与新 verified 品牌规范键不一致时阻止整个合并。
- unknown 不覆盖已有 verified/manual 品牌。
- 新 ASIN 保留完整 product type、置信度、首次与最后出现日期信息。

- [ ] **Step 4: 为 PostgreSQL 元数据专用导入写失败测试**

在 `BestSellersPostgres.Tests.ps1` 验证：

- `New-BestSellersMetadataImportSql` 只调用 `upsert_best_sellers_product_metadata`。
- SQL 不包含 snapshot、category observation 或 receipt 写入。
- `Invoke-BestSellersMetadataPostgresImport` 使用现有安全环境变量保存/恢复逻辑。
- 冲突发生时不会调用 `psql`。

- [ ] **Step 5: 实现专用 SQL 与导入器**

复用现有 metadata JSON 序列化和数据库连接参数，不复制榜单导入交易。元数据列表为空时快速成功且不调用数据库。

- [ ] **Step 6: 运行目标 Pester 测试并提交**

```powershell
Invoke-Pester -Path @('.\tests\BestSellersBrandEnrichment.Tests.ps1', '.\tests\BestSellersPostgres.Tests.ps1') -Output Detailed
git add src/BestSellersBrandEnrichment.psm1 src/BestSellersPostgres.psm1 tests/BestSellersBrandEnrichment.Tests.ps1 tests/BestSellersPostgres.Tests.ps1
git commit -m "feat: add auditable brand enrichment imports"
```

---

## Task 4: 建立历史品牌采集器与可注入的回填编排脚本

**Files:**

- Create: `scripts/python/collect_brand_enrichment.py`
- Create: `tests/python/test_collect_brand_enrichment.py`
- Create: `scripts/Invoke-BestSellersBrandBackfill.ps1`
- Create: `tests/Invoke-BestSellersBrandBackfill.Tests.ps1`

- [ ] **Step 1: 为独立 Python 采集器写失败测试**

CLI 合同：

```text
--asins-json <path>
--output <path>
--marketplace AMAZON_US
--headless true|false
```

用假 browser/page 验证每个去重 ASIN 访问一次 Amazon 详情 URL，复用 `_extract_detail_page` 与 `classify_brand_evidence`，单个 ASIN 失败只生成对应状态而不停止批次，最终 artifact 确定性排序。

运行：

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_collect_brand_enrichment -v
```

预期：脚本不存在而失败。

- [ ] **Step 2: 实现最小采集器**

采集器只负责页面访问和 artifact JSON 写出；不直接访问 PostgreSQL、D1 或历史 snapshot 文件。阻断、超时、ASIN 不匹配和冲突都形成可审计结果。

- [ ] **Step 3: 为 PowerShell 编排器写失败测试**

通过注入的 `CollectAction`、`PostgresAction`、`PublishAction` 覆盖：

- 从已核验历史 snapshot 读出唯一 ASIN 集合。
- 支持 `-MaxProducts`、`-Headless` 和 `-SkipDashboard`。
- 写入 `var/brand-enrichment/YYYY-MM-DD/amazon-brand-enrichment.json` 与对应 receipt。
- artifact/receipt 验证通过后才允许数据库导入和网站发布。
- 采集、校验、冲突或数据库失败时不发布网站。
- 重跑同一日期时先验证现有 artifact 与请求集合；不静默混合不同 ASIN 集合。

- [ ] **Step 4: 实现编排器和发布前门槛**

编排顺序固定为：发现 ASIN → 采集 → 验证 artifact → 写并验证 receipt → 合并完整元数据 → PostgreSQL 专用导入 → 可选 D1 发布。每个阶段输出简洁计数，不打印密钥。

- [ ] **Step 5: 运行目标测试并提交**

```powershell
.\.venv\Scripts\python.exe -m unittest tests.python.test_collect_brand_enrichment -v
Invoke-Pester .\tests\Invoke-BestSellersBrandBackfill.Tests.ps1 -Output Detailed
git add scripts/python/collect_brand_enrichment.py scripts/Invoke-BestSellersBrandBackfill.ps1 tests/python/test_collect_brand_enrichment.py tests/Invoke-BestSellersBrandBackfill.Tests.ps1
git commit -m "feat: orchestrate historical brand backfill"
```

---

## Task 5: 建立网站端元数据刷新合同和共享校验器

**Files:**

- Create: `web/lib/brand-metadata-refresh-contract.ts`
- Create: `web/lib/brand-metadata-refresh-contract.test.ts`
- Modify: `web/lib/sync-contract.ts`
- Modify: `web/lib/sync-contract.test.ts`

- [ ] **Step 1: 为可复用产品元数据校验器写失败测试**

从现有 sync bundle 校验中抽出并导出：

```typescript
export function validateProductMetadataRow(value: unknown): ProductMetadata
```

测试旧 bundle 的有效/无效行为完全不变，并能被新合同直接调用。

- [ ] **Step 2: 实现最小共享校验器重构**

只移动既有规则，不放宽字段、枚举、日期或品牌来源验证。先运行旧合同测试确认无回归。

- [ ] **Step 3: 为 metadata refresh 请求写失败测试**

请求结构固定为：

```typescript
interface BrandMetadataRefreshRequest {
  schemaVersion: "amazon-brand-metadata-refresh-v1";
  marketplace: "AMAZON_US";
  artifactJson: string;
  artifactSha256: string;
  receipt: BrandEnrichmentReceipt;
  productMetadata: ProductMetadata[];
}
```

测试必须验证：

- `artifactJson` 是精确原文，不先 parse/re-stringify 再算哈希。
- 对 UTF-8 `artifactJson` 计算的 SHA-256 与 `artifactSha256`、receipt 同时一致。
- artifact schema、marketplace、记录数和各状态计数与 receipt 一致。
- artifact 的排序去重 ASIN 集合哈希与 receipt 一致。
- `productMetadata` 的 ASIN 集合与 artifact 完全一致，且每行完整通过共享元数据校验。
- VERIFIED product 的 `raw_brand` 必须与 artifact 原始值一致，`brand_source` 必须为 `verified_metadata`；非 VERIFIED product 不得携带品牌值。
- 重复 ASIN、额外/缺失 ASIN、伪造计数、品牌不一致或错误哈希均拒绝。

- [ ] **Step 4: 实现刷新合同并运行测试**

```powershell
Set-Location .\web
npm test -- --run lib/sync-contract.test.ts lib/brand-metadata-refresh-contract.test.ts
Set-Location ..
git add web/lib/sync-contract.ts web/lib/sync-contract.test.ts web/lib/brand-metadata-refresh-contract.ts web/lib/brand-metadata-refresh-contract.test.ts
git commit -m "feat: validate brand metadata refresh requests"
```

---

## Task 6: 抽取共享 D1 upsert 并新增独立元数据刷新端点

**Files:**

- Create: `web/lib/product-metadata-upsert.ts`
- Create: `web/lib/product-metadata-upsert.test.ts`
- Modify: `web/app/api/sync/v1/bundles/route.ts`
- Create: `web/app/api/sync/v1/product-metadata/route.ts`
- Create: `web/tests/product-metadata-route-built.test.ts`

- [ ] **Step 1: 为共享 D1 绑定器写失败测试**

锁定现有 bundle 路由的插入/更新语义：

- 新 ASIN 可插入完整 metadata 行。
- incoming unknown 不覆盖 existing verified/manual 品牌。
- incoming verified 更新 unknown。
- 所有日期、置信度和产品类型字段使用与现有 bundle 路由相同的绑定顺序。

- [ ] **Step 2: 抽取共享 SQL 与 statement 绑定器**

把 `bundles/route.ts` 中产品元数据 upsert SQL 和参数绑定移到 `web/lib/product-metadata-upsert.ts`，旧路由改为调用共享函数。运行现有 bundle 路由与同步测试，确认生成 SQL 无语义变化。

- [ ] **Step 3: 为独立端点写失败测试**

在 build 后 route 测试中覆盖：

- 无 bearer、错误 bearer 返回 401。
- 请求合同无效返回 400，且 D1 未执行 batch。
- 已有 verified/manual 规范品牌键与 incoming verified 不同返回 409，且无任何写入。
- 合法请求只生成产品元数据 statements，并在一次 `DB.batch` 中提交。
- 端点不包含 snapshot、category、observation 或 receipt 表写入。
- 缺失的历史 ASIN 可插入完整 metadata 行。

- [ ] **Step 4: 实现冲突预检和原子写入**

新端点使用现有 `authorizeSyncRequest`。在 batch 前一次读取所有目标 ASIN 的已有品牌状态，按规范品牌键进行冲突判断；任一冲突即整体 409。无冲突后使用共享绑定器构建一次 batch。

- [ ] **Step 5: 运行网站目标测试、完整测试和构建并提交**

```powershell
Set-Location .\web
npm test -- --run lib/product-metadata-upsert.test.ts tests/product-metadata-route-built.test.ts
npm test
npm run build
npm run lint
Set-Location ..
git add web/lib/product-metadata-upsert.ts web/lib/product-metadata-upsert.test.ts web/app/api/sync/v1/bundles/route.ts web/app/api/sync/v1/product-metadata/route.ts web/tests/product-metadata-route-built.test.ts
git commit -m "feat: add atomic product metadata refresh endpoint"
```

---

## Task 7: 接通本地发布器，部署端点并做三 ASIN 代表性核验

**Files:**

- Modify: `src/BestSellersBrandEnrichment.psm1`
- Modify: `scripts/Invoke-BestSellersBrandBackfill.ps1`
- Modify: `tests/BestSellersBrandEnrichment.Tests.ps1`
- Modify: `tests/Invoke-BestSellersBrandBackfill.Tests.ps1`
- Modify: `.openai/hosting.json`（仅当 Sites 部署工具明确生成必要配置变更）

- [ ] **Step 1: 为 D1 payload 与 HTTP 发布器写失败测试**

测试 payload 保留磁盘 artifact 的精确 UTF-8 文本，附带匹配哈希、receipt 和完整 ProductMetadata 行；HTTP 请求复用现有 sync secret、使用 UTF-8 JSON body、命中 `/api/sync/v1/product-metadata`，非 2xx 时抛错且不泄露凭据。

- [ ] **Step 2: 实现 payload builder 与发布调用**

优先复用 `New-DashboardPublishRestParameters`，不要复制授权头或编码逻辑。编排器只在本地 artifact、receipt 和 PostgreSQL 导入全部成功后调用发布器。

- [ ] **Step 3: 运行本地回归测试**

```powershell
Invoke-Pester -Path @('.\tests\BestSellersBrandEnrichment.Tests.ps1', '.\tests\Invoke-BestSellersBrandBackfill.Tests.ps1') -Output Detailed
```

- [ ] **Step 4: 先部署兼容端点，再运行代表性回填**

按照 `sites:sites-hosting` 流程部署 `web`。部署完成后仅对下列 ASIN 运行：

```text
B0BVGSX46M
B089274RH8
B07HC898GM
```

允许真实覆盖率为 0–3；不得为了达到数量而放宽来源。检查每条结果的详情页 ASIN、证据来源、verification_status、artifact hash 和 receipt hash。

- [ ] **Step 5: 核验网站数据库与公开接口**

确认合法请求写入后，网站查询能看到对应品牌或 unknown 状态；重复提交相同 payload 幂等；故意构造冲突 payload 返回 409 且数据库无部分更新。

- [ ] **Step 6: 提交发布器改动**

```powershell
git add src/BestSellersBrandEnrichment.psm1 scripts/Invoke-BestSellersBrandBackfill.ps1 tests/BestSellersBrandEnrichment.Tests.ps1 tests/Invoke-BestSellersBrandBackfill.Tests.ps1
git commit -m "feat: publish audited brand metadata refreshes"
```

---

## Task 8: 执行 131 ASIN 全量回填、不可变性检查与最终验收

**Files:**

- Create: `var/brand-enrichment/2026-08-28/amazon-brand-enrichment.json`
- Create: `var/brand-enrichment/2026-08-28/amazon-brand-enrichment-receipt.json`
- Modify: `docs/audits/V2-PHASE-0-REAUDIT-2026-08-28.md`

- [ ] **Step 1: 回填前记录不可变基线**

对所有受管历史 snapshot 与 capture receipt 计算 SHA-256 清单，并记录 PostgreSQL/D1 的总 ASIN 数、known/unknown 品牌数和来源分布。将清单保存在本次运行日志或临时验证输出中，不写入历史目录。

- [ ] **Step 2: 运行全量回填**

```powershell
.\scripts\Invoke-BestSellersBrandBackfill.ps1 -MarketDate 2026-08-28 -Headless true
```

若真实脚本参数因现有仓库命名规范不同，只允许在 Task 4 实现时统一修改计划中的调用示例和脚本测试；不得保留两个含义相同的参数接口。

- [ ] **Step 3: 核验 artifact、receipt 和数据一致性**

确认：

- 请求 ASIN 数为 131，artifact 每个 ASIN 恰好一条结果。
- 各状态计数之和等于 131，verified 只来自三类可信来源。
- PostgreSQL 与 D1 的产品元数据总数、verified/unknown 数和 normalized_brand 分布一致。
- 所有 verified 原始品牌均通过 PowerShell 权威规范化。
- 回填前后历史 snapshot 与 capture receipt SHA-256 清单完全一致。
- 网站现有 2026-08-27 榜单行数和 Top 30 结构没有变化。

- [ ] **Step 4: 运行全套验证**

```powershell
Invoke-Pester .\tests -Output Detailed
.\.venv\Scripts\python.exe -m unittest discover -s tests/python -p "test_*.py" -v
Set-Location .\web
npm test
npm run build
npm run lint
Set-Location ..
```

预期：Pester、Python、web tests、build 和 lint 全部通过，且没有依赖跳过的关键验收项。

- [ ] **Step 5: 更新复核报告并提交运行证据**

只在验收数据真实可查后更新 `docs/audits/V2-PHASE-0-REAUDIT-2026-08-28.md` 的品牌覆盖率、来源分布、运行日期、artifact 路径、部署 URL 与验证计数。不得把 unknown 写成已核验品牌。

```powershell
git add var/brand-enrichment/2026-08-28/amazon-brand-enrichment.json var/brand-enrichment/2026-08-28/amazon-brand-enrichment-receipt.json docs/audits/V2-PHASE-0-REAUDIT-2026-08-28.md
git commit -m "data: backfill trusted Amazon brand metadata"
```

- [ ] **Step 6: 在下一功能切片前停止并复盘**

报告真实品牌覆盖率、unknown/blocked/conflict/mismatch 数、两端数据库一致性、历史文件不可变性和公开部署状态。到此停止；Market Context UI 作为独立后续切片，重新执行 brainstorming 与计划评审。
