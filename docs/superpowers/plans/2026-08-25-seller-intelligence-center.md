# 卖家经营情报中心 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为三个 Amazon Top 30 榜单提供可审计的每日经营预警、每周竞争策略、规格观察和行动清单。

**Architecture:** 新增独立的 seller-intelligence-v1 报告，不覆盖既有 amazon-bs-analysis-report-v1 的不可变归档。PowerShell 只从回执验证快照生成报告；D1 原样归档，网站从 D1 实时计算或读取归档。

**Tech Stack:** Windows PowerShell 5.1、Pester、TypeScript、React、Vinext、Cloudflare D1、Sites。

**Spec:** docs/superpowers/specs/2026-08-25-seller-intelligence-center-design.md

## Global Constraints

- 只使用回执验证成功的完整 Top 30；不完整数据只显示质量披露和排名事实。
- 日度比较要求相邻两天完整；明显变化 >=10，高优先级 >=20。
- 周度策略要求至少 5 个完整市场日；价格、星级、评论、优惠覆盖低于 80% 时暂停对应描述。
- 公开结论只作描述性观察，禁止因果、销量、利润或选品成功预测。
- 规格、品牌、兼容性不能明确验证时必须为 null。
- 公开 API 和正文不得泄露本机路径、邮箱、密钥、任务、数据库、备份或内部错误。
- 网站失败只标记发布失败，不阻断采集、PDF、邮件、PostgreSQL 或备份。
- 不接入大模型、不增加 API 密钥、不覆盖已有归档正文。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| src/SellerIntelligence.psm1 | 完整度、日度信号、竞品池、规格解析、哈希和 JSON 写入规则。 |
| scripts/New-SellerIntelligenceReports.ps1 | 回执门禁、历史完整日计数、生成四份每日或每周 JSON。 |
| scripts/Invoke-SellerIntelligenceBackfill.ps1 | 安全回填新报告键。 |
| scripts/Publish-BestSellersDashboard.ps1 | 健康审计后同步卖家情报。 |
| tests/SellerIntelligence.Tests.ps1 | Pester 规则与生成器测试。 |
| web/lib/seller-intelligence-contract.ts | seller-intelligence-v1 校验与脱敏。 |
| web/lib/seller-intelligence.ts | D1 实时读取模型。 |
| web/app/api/sync/v1/seller-intelligence/route.ts | Bearer 鉴权、幂等、不可变写入。 |
| web/app/api/public/seller-intelligence/** | 实时、列表和详情公开 API。 |
| web/app/analysis/SellerIntelligenceCenter.tsx | 经营预警、竞争策略、归档与产品下钻界面。 |
| web/drizzle/0002_seller_intelligence.sql | D1 不可变归档表和查询索引。 |
| web/tests/seller-intelligence*.test.mjs | 合约、同步、API、实时和渲染测试。 |

### Task 1: 定义公开报告合约

**Files:**
- Create: web/lib/seller-intelligence-contract.ts
- Create: web/tests/seller-intelligence-contract.test.mjs
- Modify: web/package.json

**Interfaces:**
- Produces: SellerIntelligenceReport, SellerSignal, SellerProfile, validateSellerIntelligenceReport(value).
- Report profiles: seller_alert, competition_strategy.
- Immutable key: seller-alert/daily/<date>/<scope>.json or competition-strategy/weekly/<date>/<scope>.json.

- [ ] **Step 1: Write the failing test**

~~~js
const alert = {
  schemaVersion: "seller-intelligence-v1",
  key: "seller-alert/daily/2026-08-24/pressure_washers.json",
  reportKind: "daily", profile: "seller_alert", marketDate: "2026-08-24",
  categoryKey: "pressure_washers", generatedAt: "2026-08-25T01:00:00Z",
  generatorVersion: "seller-rules-v1", contentSha256: "a".repeat(64),
  evidence: { complete: true, completeMarketDays: 6, sampleSize: 30, fieldCoverage: { price: 100, rating: 100, reviews: 100, discount: 100, specs: 0 } },
  signals: [{ priority: "high", kind: "rank_move", asin: "B000000001", currentRank: 4, previousRank: 26, checks: ["核查价格与优惠状态"], evidence: ["排名由 #26 上升至 #4"] }],
  sections: [{ title: "经营预警", statements: ["发现 1 个高优先级待核查变化。"] }],
  limitations: ["描述性观察，不代表销量或利润预测。"]
};
test("accepts an auditable seller alert", () => assert.equal(validateSellerIntelligenceReport(alert).ok, true));
test("rejects weekly trend below five complete days", () => assert.equal(validateSellerIntelligenceReport({ ...alert, reportKind: "weekly", profile: "competition_strategy", evidence: { ...alert.evidence, completeMarketDays: 4 }, sections: [{ title: "周度趋势", statements: ["趋势稳定"] }] }).ok, false));
~~~

- [ ] **Step 2: Run the test to verify it fails**

Run: pnpm exec node --test tests/seller-intelligence-contract.test.mjs

Expected: FAIL because the contract module does not exist.

- [ ] **Step 3: Implement the minimal contract**

~~~ts
export type SellerProfile = "seller_alert" | "competition_strategy";
export type SellerPriority = "high" | "medium" | "low";
export type SellerSignal = { priority: SellerPriority; kind: "rank_move" | "top10_entry" | "top10_exit" | "top30_entry" | "top30_exit" | "discount_change"; asin: string; currentRank: number | null; previousRank: number | null; checks: string[]; evidence: string[] };
export type SellerIntelligenceReport = { schemaVersion: "seller-intelligence-v1"; key: string; reportKind: "daily" | "weekly"; profile: SellerProfile; marketDate: string; categoryKey: string | null; generatedAt: string; generatorVersion: string; contentSha256: string; evidence: { complete: boolean; completeMarketDays: number; sampleSize: number; fieldCoverage: Record<"price" | "rating" | "reviews" | "discount" | "specs", number> }; signals: SellerSignal[]; sections: { title: string; statements: string[] }[]; limitations: string[] };
export function validateSellerIntelligenceReport(value: unknown) { /* validate every field and return { ok, report|errors } */ }
~~~

Validate exact key/profile pairing, known category, SHA-256, 0–100 coverage, non-empty signal evidence, private operational text and the five-complete-day trend gate.

- [ ] **Step 4: Run all website tests**

Run: pnpm test

Expected: new contract tests and all existing tests pass.

- [ ] **Step 5: Commit**

~~~powershell
git add web/lib/seller-intelligence-contract.ts web/tests/seller-intelligence-contract.test.mjs web/package.json
git commit -m "feat: define seller intelligence contract"
~~~

### Task 2: Implement deterministic rules and specification parser

**Files:**
- Create: src/SellerIntelligence.psm1
- Create: tests/SellerIntelligence.Tests.ps1

**Interfaces:**
- Produces: Test-SellerExactTop30, Get-SellerDailySignals, Get-SellerCompetitorPool, Get-SellerSpecifications, New-SellerIntelligenceReports, Write-SellerIntelligenceReports.
- Inputs: verified observations with rank, asin, title, price, rating, reviews, has_discount and discounts.

- [ ] **Step 1: Write failing Pester tests**

~~~powershell
Describe 'Seller intelligence rules' {
  It 'marks a twenty-two-place improvement high' {
    $signals = @(Get-SellerDailySignals -Current @([pscustomobject]@{ asin='B000000001'; rank=4; title='2000 PSI Electric Pressure Washer'; has_discount=$true }) -Previous @([pscustomobject]@{ asin='B000000001'; rank=26; title='2000 PSI Electric Pressure Washer'; has_discount=$false }))
    $signals[0].priority | Should Be 'high'
    $signals[0].checks | Should Contain '核查价格与优惠状态'
  }
  It 'suppresses rank signals without two exact Top 30 lists' { (Get-SellerDailySignals -Current @() -Previous @()).Count | Should Be 0 }
  It 'extracts only explicit washer values' {
    $specs = Get-SellerSpecifications -CategoryKey pressure_washers -Title '2000 PSI 1.8 GPM Electric Pressure Washer with 25 FT Hose'
    $specs.psi | Should Be 2000; $specs.gpm | Should Be 1.8; $specs.power_type | Should Be 'electric'; $specs.hose_length_ft | Should Be 25
  }
  It 'keeps absent sump-pump values null' { (Get-SellerSpecifications -CategoryKey sump_pumps -Title 'Reliable pump').head_ft | Should Be $null }
}
~~~

- [ ] **Step 2: Run tests to verify they fail**

Run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test.ps1

Expected: FAIL because the module and functions do not exist.

- [ ] **Step 3: Implement pure rules**

~~~powershell
function Get-SellerDailySignals {
  param([object[]]$Current, [object[]]$Previous)
  if (-not (Test-SellerExactTop30 $Current) -or -not (Test-SellerExactTop30 $Previous)) { return @() }
  # Match by ASIN: >=20 high; 10–19 medium; emit Top 10/30 and verifiable discount changes.
}
function Get-SellerSpecifications {
  param([ValidateSet('pressure_washers','sump_pumps','pressure_washer_accessories')][string]$CategoryKey,[string]$Title)
  # Match only explicit PSI/GPM/FT/HP/V/degree/size tokens; all unmatched properties are $null.
}
~~~

Implement the pool only when complete market days >=5. Use continuous presence, Top 10 appearances, latest rank and maximum absolute movement to assign high/medium/low observation priority. Encode new Chinese PowerShell constants via UTF-8 Base64, matching the existing module’s Windows PowerShell 5.1 compatibility pattern.

- [ ] **Step 4: Verify implementation**

Run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test.ps1

Expected: all Pester tests pass.

- [ ] **Step 5: Commit**

~~~powershell
git add src/SellerIntelligence.psm1 tests/SellerIntelligence.Tests.ps1
git commit -m "feat: add seller intelligence rules"
~~~

### Task 3: Generate and backfill immutable seller reports

**Files:**
- Create: scripts/New-SellerIntelligenceReports.ps1
- Create: scripts/Invoke-SellerIntelligenceBackfill.ps1
- Modify: tests/SellerIntelligence.Tests.ps1

**Interfaces:**
- New-SellerIntelligenceReports.ps1 accepts SnapshotPath, SnapshotsRoot, ReportKind Daily|Weekly and OutputRoot.
- It returns Status, MarketDate, CompleteMarketDays, ReportPaths and ReportCount.
- It creates overview plus three category reports.
- Backfill POSTs only to /api/sync/v1/seller-intelligence and never prints AMAZON_BS_DASHBOARD_SYNC_SECRET.

- [ ] **Step 1: Write failing generation tests**

~~~powershell
It 'writes four seller alert JSON files with distinct keys' {
  $result = & (Join-Path $projectRoot 'scripts\New-SellerIntelligenceReports.ps1') -SnapshotPath $fixtureSnapshot -OutputRoot $TestDrive | ConvertFrom-Json
  $result.Status | Should Be 'CREATED'; $result.ReportCount | Should Be 4
  @($result.ReportPaths | ForEach-Object { (Get-Content $_ -Raw | ConvertFrom-Json).key } | Select-Object -Unique).Count | Should Be 4
}
It 'keeps an incomplete snapshot to a quality disclosure' {
  $report = New-SellerIntelligenceReport -Snapshot $incomplete -ReceiptSha256 ('a' * 64) -Profile SellerAlert
  ($report.signals | Measure-Object).Count | Should Be 0
  ($report.sections | ConvertTo-Json -Depth 8) | Should Match '暂不下结论'
}
~~~

- [ ] **Step 2: Run tests to verify failure**

Run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test.ps1

Expected: FAIL because the generator script does not exist.

- [ ] **Step 3: Implement receipt-gated generator and uploader**

~~~powershell
$receiptValidation = & (Join-Path $projectRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath | ConvertFrom-Json
if (-not $receiptValidation.valid) { throw 'Seller intelligence reports require a valid capture receipt.' }
$reports = @(New-SellerIntelligenceReports -Snapshot $snapshot -ReceiptSha256 ([string]$receiptValidation.actual_snapshot_sha256) -Profile $profile -CompleteMarketDays $completeMarketDays)
$paths = @(Write-SellerIntelligenceReports -Reports $reports -OutputDirectory $OutputRoot)
~~~

The backfill script must validate each receipt, accept only imported or duplicate responses, and throw for every other response. It may upload quality-disclosure reports, but no incomplete report may contain trend, pool or association claims.

- [ ] **Step 4: Smoke-test without network side effects**

Run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\New-SellerIntelligenceReports.ps1 -SnapshotPath .\var\amazon-bestsellers\2026-08-24\amazon-bestsellers.json -OutputRoot $env:TEMP\seller-intelligence-smoke

Expected: Status CREATED, ReportCount 4 and four parseable JSON files.

- [ ] **Step 5: Run tests and commit**

~~~powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test.ps1
git add src/SellerIntelligence.psm1 scripts/New-SellerIntelligenceReports.ps1 scripts/Invoke-SellerIntelligenceBackfill.ps1 tests/SellerIntelligence.Tests.ps1
git commit -m "feat: generate seller intelligence reports"
~~~

### Task 4: Add D1 immutable archive and secure sync

**Files:**
- Create: web/drizzle/0002_seller_intelligence.sql
- Modify: web/db/schema.ts
- Modify: web/lib/d1.ts
- Create: web/app/api/sync/v1/seller-intelligence/route.ts
- Create: web/tests/seller-intelligence-sync-route.test.mjs

**Interfaces:**
- Table seller_intelligence_reports: key, report_kind, profile, market_date, category_key, generated_at, generator_version, content_sha256, content_json, imported_at.
- POST returns imported or duplicate; same key with another hash is HTTP 409 immutable_key_conflict.

- [ ] **Step 1: Write failing sync tests**

~~~js
test("stores a valid report once and returns duplicate for the same hash", async () => {
  assert.equal((await POST(authenticatedRequest(alert))).status, 200);
  assert.equal((await (await POST(authenticatedRequest(alert))).json()).status, "duplicate");
});
test("rejects a changed body under the same immutable key", async () => {
  assert.equal((await POST(authenticatedRequest({ ...alert, contentSha256: "b".repeat(64) }))).status, 409);
});
~~~

- [ ] **Step 2: Run test to verify failure**

Run: pnpm exec node --test tests/seller-intelligence-sync-route.test.mjs

Expected: FAIL because the route does not exist.

- [ ] **Step 3: Implement migration and route**

~~~sql
CREATE TABLE IF NOT EXISTS seller_intelligence_reports (
  key TEXT PRIMARY KEY, report_kind TEXT NOT NULL, profile TEXT NOT NULL, market_date TEXT NOT NULL,
  category_key TEXT, generated_at TEXT NOT NULL, generator_version TEXT NOT NULL,
  content_sha256 TEXT NOT NULL, content_json TEXT NOT NULL, imported_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS seller_intelligence_reports_lookup ON seller_intelligence_reports (market_date DESC, report_kind, profile, category_key);
~~~

Follow existing assertSyncAuthorization semantics. Validate first, query by key with parameterized SQL, return duplicate for identical hash, 409 for a different hash, and insert through one D1 batch only when absent.

- [ ] **Step 4: Verify website suite**

Run: pnpm test; pnpm lint

Expected: sync tests, migrations and existing suite pass with zero lint errors.

- [ ] **Step 5: Commit**

~~~powershell
git add web/drizzle/0002_seller_intelligence.sql web/db/schema.ts web/lib/d1.ts web/app/api/sync/v1/seller-intelligence/route.ts web/tests/seller-intelligence-sync-route.test.mjs
git commit -m "feat: archive seller intelligence reports"
~~~

### Task 5: Build safe live and archive read models

**Files:**
- Create: web/lib/seller-intelligence.ts
- Create: web/app/api/public/seller-intelligence/route.ts
- Create: web/app/api/public/seller-intelligence/[...key]/route.ts
- Create: web/app/api/public/seller-intelligence/live/route.ts
- Create: web/tests/seller-intelligence-public-routes.test.mjs

**Interfaces:**
- buildLiveSellerIntelligence(data, { profile, categoryKey }) returns a validated SellerIntelligenceReport.
- Public list supports profile, category and YYYY-MM-DD date.
- Live reads D1 only and never writes.

- [ ] **Step 1: Write failing API tests**

~~~js
test("suppresses signals for an incomplete category", async () => {
  const report = await buildLiveSellerIntelligence(incompleteDashboard, { profile: "seller_alert", categoryKey: "sump_pumps" });
  assert.equal(report.signals.length, 0);
  assert.match(report.sections.flatMap((s) => s.statements).join(" "), /暂不下结论/);
});
test("emits a high alert only for two complete comparison days", async () => {
  const report = await buildLiveSellerIntelligence(completeDashboardWithTwentyRankMove, { profile: "seller_alert", categoryKey: "pressure_washers" });
  assert.equal(report.signals[0].priority, "high");
});
test("does not expose operational details from public routes", async () => {
  assert.doesNotMatch(JSON.stringify(await (await GET(publicRequest())).json()), /C:\\Users|SMTP|secret|746254487/i);
});
~~~

- [ ] **Step 2: Run test to verify failure**

Run: pnpm exec node --test tests/seller-intelligence-public-routes.test.mjs

Expected: FAIL because the service and public routes do not exist.

- [ ] **Step 3: Implement the read model**

~~~ts
export async function buildLiveSellerIntelligence(data: LiveDashboard, options: { profile: SellerProfile; categoryKey: CategoryKey | null }): Promise<SellerIntelligenceReport> {
  // Build seller_alert only for exact current/previous Top 30.
  // Build competition_strategy only at five complete market days.
  // Emit quality disclosure rather than unavailable data as zero.
}
~~~

Validate query values before D1 access. Return safe empty lists for a database error; validate persisted JSON with the contract before returning detail content.

- [ ] **Step 4: Run all website tests**

Run: pnpm test

Expected: public read, complete-day gate and privacy tests all pass.

- [ ] **Step 5: Commit**

~~~powershell
git add web/lib/seller-intelligence.ts web/app/api/public/seller-intelligence web/tests/seller-intelligence-public-routes.test.mjs
git commit -m "feat: expose seller intelligence read models"
~~~

### Task 6: Add seller workspace and product drilldown

**Files:**
- Create: web/app/analysis/SellerIntelligenceCenter.tsx
- Modify: web/app/analysis/page.tsx
- Modify: web/app/enhancements.css
- Modify: web/app/products/[asin]/page.tsx
- Modify: web/tests/rendered-html.test.mjs

**Interfaces:**
- The client supports seller_alert, competition_strategy and archive mode, with category and date filters.
- Signal cards link only valid ASINs to /products/[asin].

- [ ] **Step 1: Write failing render tests**

~~~js
test("renders alerts, strategy and evidence-first disclosure", async () => {
  const html = await (await render("/analysis", sellerIntelligenceEnvironment())).text();
  assert.match(html, /经营预警/); assert.match(html, /竞争策略/); assert.match(html, /描述性观察/);
  assert.doesNotMatch(html, /销量预测|利润预测|C:\\Users|SMTP/i);
});
test("uses the strategy empty state below five complete days", async () => {
  assert.match(await (await render("/analysis", sellerIntelligenceEnvironment({ completeMarketDays: 4 }))).text(), /数据积累中，暂不输出稳定趋势/);
});
~~~

- [ ] **Step 2: Run render tests to verify failure**

Run: pnpm exec node --test tests/rendered-html.test.mjs

Expected: FAIL because seller workspace labels and data are absent.

- [ ] **Step 3: Implement accessible UI**

~~~tsx
const [profile, setProfile] = useState<SellerProfile>("seller_alert");
<button aria-pressed={profile === "seller_alert"} onClick={() => changeProfile("seller_alert")}>经营预警</button>
<button aria-pressed={profile === "competition_strategy"} onClick={() => changeProfile("competition_strategy")}>竞争策略</button>
~~~

Render signal priority, ASIN, current/previous ranks, evidence and checks. Strategy cards display price-band, top stability, competitor-pool and specification availability only when the corresponding evidence gate passes. Product pages show explicit non-null specifications and never display missing values as zero.

- [ ] **Step 4: Verify responsive site behavior**

Run: pnpm test; pnpm lint

Expected: rendered route, filter, empty-state, drilldown and lint tests pass.

- [ ] **Step 5: Commit**

~~~powershell
git add web/app/analysis/SellerIntelligenceCenter.tsx web/app/analysis/page.tsx web/app/enhancements.css web/app/products/[asin]/page.tsx web/tests/rendered-html.test.mjs
git commit -m "feat: add seller intelligence workspace"
~~~

### Task 7: Integrate publishing, backfill and full regression

**Files:**
- Modify: scripts/Publish-BestSellersDashboard.ps1
- Modify: tests/DashboardPublishing.Tests.ps1
- Modify: README.md

**Interfaces:**
- Daily health success uploads four seller_alert reports.
- Weekly report availability plus health success uploads four competition_strategy reports.
- New endpoint failure marks only dashboard publication as failed.

- [ ] **Step 1: Write failing publisher tests**

~~~powershell
It 'generates seller alerts after the health gate' {
  $script = Get-Content (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw
  $script | Should Match 'New-SellerIntelligenceReports.ps1'
  $script | Should Match '/api/sync/v1/seller-intelligence'
  $script.IndexOf('Test-BestSellersDailyOperationalHealth.ps1') | Should BeLessThan $script.IndexOf('New-SellerIntelligenceReports.ps1')
}
It 'keeps seller intelligence outside the mail path' {
  (Get-Content (Join-Path $projectRoot 'scripts\Run-BestSellersDaily.ps1') -Raw) | Should Not Match 'seller-intelligence'
}
~~~

- [ ] **Step 2: Run the PowerShell suite to verify failure**

Run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test.ps1

Expected: FAIL because the publisher does not reference the new generator.

- [ ] **Step 3: Add controlled publisher step**

~~~powershell
$sellerRun = & (Join-Path $sourceRoot 'scripts\New-SellerIntelligenceReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind Daily | ConvertFrom-Json
if ([string]$sellerRun.Status -ne 'CREATED' -or [int]$sellerRun.ReportCount -ne 4) { throw 'Seller alert reports were not created.' }
$sellerEndpoint = [uri]::new($DashboardUrl, '/api/sync/v1/seller-intelligence')
foreach ($sellerPath in @($sellerRun.ReportPaths)) {
  Invoke-RestMethod -Uri $sellerEndpoint -Method Post -Headers $headers -ContentType 'application/json' -InFile $sellerPath | Out-Null
}
~~~

Repeat the step with ReportKind Weekly only when the existing weekly JSON exists. Update README with Top 30 gates, 80% field gate, five-day strategy gate, null specification behavior and the non-causal “待核查” meaning.

- [ ] **Step 4: Run smoke, full tests and controlled backfill**

~~~powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\New-SellerIntelligenceReports.ps1 -SnapshotPath .\var\amazon-bestsellers\2026-08-24\amazon-bestsellers.json -OutputRoot $env:TEMP\seller-intelligence-final
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test.ps1
Set-Location .\web; pnpm test; pnpm lint; Set-Location ..
~~~

Expected: four parseable smoke-report files, zero PowerShell failures, zero website failures and zero lint errors. After website deployment and only with the configured secret, run Invoke-SellerIntelligenceBackfill.ps1; accepted responses are imported or duplicate only.

- [ ] **Step 5: Commit**

~~~powershell
git add scripts/Publish-BestSellersDashboard.ps1 tests/DashboardPublishing.Tests.ps1 README.md
git commit -m "feat: publish seller intelligence automatically"
~~~

## Plan Self-Review

- Daily alerts, weekly strategy, competitor pool, price-band, title specifications, immutable archiving, sync, public reads, UI, automation and tests each map to Tasks 1–7.
- The contract names, profiles, endpoint, key format and gate values are consistent across tasks.
- Every task follows failing test, failure confirmation, minimal implementation, verification and commit.
