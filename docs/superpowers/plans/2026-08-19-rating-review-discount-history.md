# 评分、评论、优惠与排名关联 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 抓取并核验 Best Sellers Top 30 的评分、评论数和公开优惠，将优惠历史入库，并在日报和周报中展示其与排名的非因果关联。

**Architecture:** 列表卡片只提供排名、ASIN、标题、价格、评分和评论数；价格完整性通过后才以规范详情页逐个核验优惠。快照将结构化优惠状态传给 PostgreSQL；周度分析仅对相邻有效日期、同类目同 ASIN 的已知优惠状态形成变化记录。

**Tech Stack:** Python 3 + Playwright、PowerShell/Pester、PostgreSQL JSONB/PLpgSQL、Markdown/HTML/PDF。

**Spec:** docs/superpowers/specs/2026-08-18-rating-review-discount-history-design.md

## Global Constraints

- 评分只来自星级标签；评论数只来自紧邻星级链接的评论文本；二者不得共用选择器或数字解析输入。
- 评分保留一位小数，评论数为非负整数；未展示时为 null。
- 仅公开 Coupon、可核验的划线价/当前价差额、Prime 专享优惠可认定为优惠。
- has_discount=true、false、null 分别是确认有优惠、确认无优惠、无法核验；未知优惠不得影响现有价格完整性发布门槛。
- 详情页仅使用 https://www.amazon.com/dp/<ASIN>；不得登录、绕过验证码或持久化认证状态。
- 价格证据和优惠证据必须独立、已脱敏；绝不存储页面正文、任意 URL、Cookie、凭据或异常消息。
- 报表只能说明观察到的共同变化，不得称优惠导致排名变化。
- 数据库迁移只向前；历史的未知优惠状态保持有效。

---

### Task 1: 完成采集器的评分、评论和优惠核验

**Files:**
- Modify: scripts/python/collect_best_sellers.py:91-180, 620-760, 870-1040
- Modify: tests/python/test_best_sellers_collector.py

**Interfaces:**
- Consumes: parse_card(card: dict) -> dict、verify_chart_prices(context, charts)。
- Produces: classify_detail_discounts(page: dict) -> dict，结果包含 has_discount: bool | None 和 discounts: list[dict[str, str]]；verify_chart_discounts(context, charts) -> tuple[list[dict], list[dict]]。

- [ ] **Step 1: 写出失败的独立评分/评论和详情页状态测试**

    def test_rating_is_rounded_to_one_decimal_without_using_review_count():
        item = parse_card({"rank": "1", "asin": "B012345678", "title": "X",
                           "rating": "4.65 out of 5 stars", "reviews": "13,471"})
        assert item["rating"] == 4.7
        assert item["reviews"] == 13471

    def test_classifies_coupon_price_drop_prime_none_and_blocked():
        assert classify_detail_discounts({"title": "X", "coupon": "Save 10%",
            "current_price": None, "list_price": None, "prime_discount": None}) == {
            "has_discount": True, "discounts": [{"kind": "COUPON", "amount": "10% off"}]}
        assert classify_detail_discounts({"blocked": True, "title": None}) == {
            "has_discount": None, "discounts": []}

- [ ] **Step 2: 运行定向测试并确认失败**

Run: & .venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector -v

Expected: 新增断言在缺失或不完整行为上失败。

- [ ] **Step 3: 实现最小提取、分类与安全导航**

    def _parse_rating(value: Any) -> float | None:
        match = re.search(r"(\d+(?:\.\d+)?)\s+out of 5 stars", str(value or ""))
        return round(float(match.group(1)), 1) if match else None

    def classify_detail_discounts(page: dict[str, Any]) -> dict[str, Any]:
        if page.get("blocked") or not page.get("title"):
            return {"has_discount": None, "discounts": []}
        # Append only normalized COUPON, PRICE_DROP and PRIME_EXCLUSIVE entries.

Keep reviews restricted to a[href*="/product-reviews/"] .a-size-small and rating to the star-label attribute. Canonicalize ASIN before navigation; extract only public signals; normalize only supported amount patterns; close every tab in finally; return unknown for blocked, invalid ASIN, navigation and extraction errors.

- [ ] **Step 4: 将核验接入成功尝试和安全诊断**

    charts, price_evidence, failures = verify_chart_prices(context, charts)
    failures = validate_collection_attempt(config, charts, failures, price_evidence)
    if failures:
        return charts, price_evidence, failures, []
    charts, discount_evidence = verify_chart_discounts(context, charts)
    return charts, price_evidence, [], discount_evidence

Extend the sanitizer with a separate discount_evidence and DiscountVerificationCount. Keep only canonical category/ASIN/detail URL and fixed status enums.

- [ ] **Step 5: 运行采集器全量测试**

Run: & .venv\Scripts\python.exe -m unittest discover -s tests/python -v

Expected: PASS；覆盖 Coupon、降价、Prime、无优惠、未知、清理、成功时 90 项详情页核验和不完整时零详情页。

- [ ] **Step 6: 提交**

    git add scripts/python/collect_best_sellers.py tests/python/test_best_sellers_collector.py
    git commit -m "feat: collect verified product discounts"

### Task 2: 将优惠状态和优惠列表持久化至 PostgreSQL

**Files:**
- Create: db/migrations/011_best_sellers_discount_history.sql
- Modify: tests/AmazonIntelligence.Tests.ps1:300-340, 720-920

**Interfaces:**
- Consumes: observation {has_discount: bool|null, discounts: [{kind, amount}]}。
- Produces: best_sellers_observation.has_discount boolean NULL、discounts jsonb NOT NULL DEFAULT []::jsonb 和扩展后的 best_sellers_daily_current/best_sellers_daily_change。

- [ ] **Step 1: 写出迁移和导入的失败测试**

    It 'stores structured true false and unknown discount states' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\011_best_sellers_discount_history.sql') -Raw
        $sql | Should Match 'ADD COLUMN has_discount boolean'
        $sql | Should Match 'ADD COLUMN discounts jsonb'
        $sql | Should Match "v_item->'discounts'"
    }

- [ ] **Step 2: 运行测试，确认其失败**

Run: Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -TestName 'stores structured true false and unknown discount states' -Output Detailed

Expected: FAIL，因为迁移尚不存在。

- [ ] **Step 3: 实现前向迁移、原子导入和视图扩展**

    ALTER TABLE best_sellers_observation
        ADD COLUMN has_discount boolean,
        ADD COLUMN discounts jsonb NOT NULL DEFAULT '[]'::jsonb,
        ADD CONSTRAINT ck_best_sellers_observation_discounts_array
            CHECK (jsonb_typeof(discounts) = 'array');

Recreate ingest_best_sellers_snapshot to insert NULLIF(v_item->>'has_discount','')::boolean and COALESCE(v_item->'discounts','[]'::jsonb), and recreate dependent views with the new typed columns. Reject malformed discount entries: only COUPON, PRICE_DROP and PRIME_EXCLUSIVE with a non-empty amount. Old snapshots map to unknown/empty list.

- [ ] **Step 4: 添加 true、false、null 与列表的导入夹具断言**

    $payload.pressure_washers[0].has_discount = $true
    $payload.pressure_washers[0].discounts = @(@{ kind='COUPON'; amount='10% off' })
    $payload.pressure_washers[1].has_discount = $false
    $payload.pressure_washers[2].has_discount = $null

Assert generated import SQL preserves the three states without converting null to false.

- [ ] **Step 5: 运行数据库相关 Pester**

Run: Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -Output Detailed

Expected: PASS；迁移、SQL 生成、旧快照兼容性通过。

- [ ] **Step 6: 提交**

    git add db/migrations/011_best_sellers_discount_history.sql tests/AmazonIntelligence.Tests.ps1
    git commit -m "feat: persist best sellers discount history"

### Task 3: 在日报中展示优惠及类目汇总

**Files:**
- Modify: src/BestSellersDailyReport.psm1:32-120
- Modify: tests/AmazonIntelligence.Tests.ps1:700-900

**Interfaces:**
- Consumes: rating、reviews、has_discount、discounts。
- Produces: Format-BestSellersDiscountDisplay -Item $item -> string，以及 Markdown/HTML 的优惠列和类目三态汇总。

- [ ] **Step 1: 写出日报渲染失败测试**

    It 'renders rating reviews discounts and category discount totals in daily reports' {
        $snapshot.pressure_washers[0].rating = 4.6
        $snapshot.pressure_washers[0].reviews = 13471
        $snapshot.pressure_washers[0].has_discount = $true
        $snapshot.pressure_washers[0].discounts = @(@{kind='COUPON'; amount='10% off'})
        $snapshot.pressure_washers[1].has_discount = $false
        $snapshot.pressure_washers[2].has_discount = $null
        $result = New-BestSellersDailyReport -CurrentSnapshot $snapshot -OutputDirectory $TestDrive
        (Get-Content $result.MarkdownPath -Raw) | Should Match '10% off'
        (Get-Content $result.MarkdownPath -Raw) | Should Match 'Pending verification'
    }

- [ ] **Step 2: 运行失败测试**

Run: Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -TestName 'renders rating reviews discounts and category discount totals in daily reports' -Output Detailed

Expected: FAIL，因为当前没有优惠列。

- [ ] **Step 3: 实现统一格式化与 Markdown/HTML 呈现**

    function Format-BestSellersDiscountDisplay {
        param($Item)
        if ($null -eq $Item.has_discount) { return 'Pending verification' }
        if (-not [bool]$Item.has_discount) { return 'None' }
        return (@($Item.discounts | ForEach-Object { $_.amount } | Where-Object { $_ }) -join '; ')
    }

Add a Discount column and verified-discounted/verified-none/unknown category summary in both formats. Preserve HTML escaping and append the fixed non-causal disclosure.

- [ ] **Step 4: 运行日报测试**

Run: Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -Output Detailed

Expected: PASS；三态、金额、汇总和 HTML 转义均通过。

- [ ] **Step 5: 提交**

    git add src/BestSellersDailyReport.psm1 tests/AmazonIntelligence.Tests.ps1
    git commit -m "feat: show discounts in daily best sellers reports"

### Task 4: 在周度分析和周报中呈现优惠-排名观察

**Files:**
- Modify: src/BestSellersWeeklyAnalysis.psm1:1-220
- Modify: src/BestSellersWeeklyReportContent.psm1:1-140
- Modify: tests/AmazonIntelligence.Tests.ps1:928-1090

**Interfaces:**
- Consumes: 有序快照的 has_discount、discounts、rank、market_date。
- Produces: discount_transitions 条目包含 category、asin、previous_market_date、market_date、previous_has_discount、has_discount、previous_discounts、discounts、previous_rank、current_rank、rank_change、transition_kind，及 discount_summary。

- [ ] **Step 1: 写出同 ASIN、相邻有效日、未知排除的失败测试**

    It 'reports only valid same-ASIN discount transitions with rank changes' {
        $day1.pressure_washers[0].has_discount = $false
        $day2.pressure_washers[0].has_discount = $true
        $day2.pressure_washers[0].discounts = @(@{kind='PRICE_DROP'; amount='$10.00 off'})
        $day2.pressure_washers[1].has_discount = $null
        $analysis = New-BestSellersWeeklyAnalysis -Snapshots @($day1, $day2)
        $transition = @($analysis.discount_transitions | Where-Object asin -eq $day2.pressure_washers[0].asin)[0]
        $transition.transition_kind | Should Be 'DISCOUNT_ADDED'
        $transition.rank_change | Should Be ($day1.pressure_washers[0].rank - $day2.pressure_washers[0].rank)
        @($analysis.discount_transitions | Where-Object asin -eq $day2.pressure_washers[1].asin).Count | Should Be 0
    }

- [ ] **Step 2: 运行失败测试**

Run: Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -TestName 'reports only valid same-ASIN discount transitions with rank changes' -Output Detailed

Expected: FAIL，因为还没有 discount_transitions。

- [ ] **Step 3: 实现状态比较、变化和统计**

    function Get-BestSellersDiscountTransitionKind {
        param($PreviousItem, $CurrentItem)
        if ($null -eq $PreviousItem.has_discount -or $null -eq $CurrentItem.has_discount) { return $null }
        if (-not $PreviousItem.has_discount -and $CurrentItem.has_discount) { return 'DISCOUNT_ADDED' }
        if ($PreviousItem.has_discount -and -not $CurrentItem.has_discount) { return 'DISCOUNT_REMOVED' }
        if (($PreviousItem.discounts | ConvertTo-Json -Compress) -ne ($CurrentItem.discounts | ConvertTo-Json -Compress)) { return 'DISCOUNT_AMOUNT_CHANGED' }
        return 'UNCHANGED'
    }

For adjacent pairs, compare only ASINs in both category maps and known states. Count unknown paired records but do not emit them as state-change events. Missing legacy lists become @().

- [ ] **Step 4: 写出并实现周报优惠排名区块**

    $sections = New-BestSellersWeeklyCategorySections -CategoryKey 'pressure_washers' -WeeklyAnalysis $analysis -RankInfluence $influence
    $sections.Markdown | Should Match 'DISCOUNT_ADDED'
    $sections.Markdown | Should Match 'observed co-movement only'

Render dates, ASIN, prior/current offer text, prior/current rank, rank change; show totals for added, removed, amount changed, unchanged, unknown; retain all current sections and render the same disclosure in HTML.

- [ ] **Step 5: 运行周度分析和周报测试**

Run: Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -Output Detailed

Expected: PASS；新增、取消、金额变化、不变、未知和非因果说明均有覆盖。

- [ ] **Step 6: 提交**

    git add src/BestSellersWeeklyAnalysis.psm1 src/BestSellersWeeklyReportContent.psm1 tests/AmazonIntelligence.Tests.ps1
    git commit -m "feat: report discount rank observations weekly"

### Task 5: 当前数据更新、端到端验收与运行手册

**Files:**
- Modify: docs/phase-7/MAINTENANCE-RUNBOOK.md
- Modify: tests/AmazonIntelligence.Tests.ps1

**Interfaces:**
- Consumes: 完整快照、回执、现有 PostgreSQL 导入器和报告命令。
- Produces: 当日快照、已导入行、无邮件日报/周报和可复核的验收结果。

- [ ] **Step 1: 写出运行手册验收测试**

    It 'documents verified import and no-email report generation' {
        $runbook = Get-Content (Join-Path $projectRoot 'docs\phase-7\MAINTENANCE-RUNBOOK.md') -Raw
        $runbook | Should Match 'Collect-BestSellers'
        $runbook | Should Match 'SkipEmail'
        $runbook | Should Match 'Pending verification'
    }

- [ ] **Step 2: 运行全量自动化基线**

Run: & .venv\Scripts\python.exe -m unittest discover -s tests/python -v; Invoke-Pester -Path tests -Output Detailed

Expected: PASS；无跳过、无无关失败。

- [ ] **Step 3: 更新手册并抓取当前真实数据**

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\Collect-BestSellers.ps1 -MarketDate 2026-08-19

Document COMPLETE-only publication, unknown discount meaning, and mandatory -SkipEmail. Before import, inspect receipt/snapshot: each selected category has 30 unique ASINs and ranks; unknown discounts are permitted but incomplete price data is not.

- [ ] **Step 4: 导入已验证快照并生成无邮件日报和周报**

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\Import-BestSellersPostgres.ps1 -SnapshotPath var\amazon-bestsellers\2026-08-19\amazon-bestsellers.json
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\New-BestSellersDailyReport.ps1 -MarketDate 2026-08-19 -SkipEmail
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\New-BestSellersWeeklyReport.ps1 -ReportDate 2026-08-19 -SkipEmail

Use only the existing script's documented parameters if its checked interface differs; do not inject credentials or send email.

- [ ] **Step 5: 核验快照、数据库和报表一致性**

    # Compare representative ASINs across snapshot, best_sellers_daily_current,
    # Markdown/HTML/PDF: rating, reviews, has_discount, discounts, rank, category.

Also scan diagnostics for page HTML, raw query URLs, cookie/credential markers and exception messages. If collection is not COMPLETE, do not import or overwrite the canonical snapshot; preserve safe failure artifacts and stop the live-data steps.

- [ ] **Step 6: 最终验证与提交**

Run: & .venv\Scripts\python.exe -m unittest discover -s tests/python -v; Invoke-Pester -Path tests -Output Detailed; git diff --check

Expected: all PASS and diff check exits 0.

    git add docs/phase-7/MAINTENANCE-RUNBOOK.md tests/AmazonIntelligence.Tests.ps1
    git commit -m "docs: document discount collection operations"

## Self-review

- Spec coverage: Task 1 covers strict collection and unknown behavior; Task 2 covers forward migration and atomic ingestion; Task 3 covers daily display; Task 4 covers valid same-ASIN transition/rank observation; Task 5 covers live current-data update, report generation and safety.
- Placeholder scan: no TBD/TODO or unspecified test work remains; the live importer command explicitly defers only to the existing approved interface.
- Type consistency: all layers use rating, reviews, has_discount, discounts; weekly output consistently uses previous_has_discount, previous_discounts, has_discount, discounts.

