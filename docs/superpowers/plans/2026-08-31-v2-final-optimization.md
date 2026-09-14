# Amazon BS Market Radar V2.0 Final Optimization Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Use test-driven-development for every behavior change and verification-before-completion before final delivery.

**Goal:** 彻底统一 Raw Amazon Ranking 与 Machines Analytical Market，使整机上下文中的 KPI、信号、品牌、产品和活动全部只基于整机，同时完成分类、市场浏览、格式化、状态与方法说明收尾。

**Architecture:** 保留现有 Next/Vinext、D1 与 dashboard 读模型。原始 `category.observations` 永远不改写；通过一个共享分析市场投影生成 Machines 行、比较、信号、品牌与覆盖指标。页面不得自行重复筛选或自行定义品牌分母。

**Tech Stack:** TypeScript/React/Vinext、Node test runner、PowerShell/Pester、现有 CSS tokens、OpenAI Sites。

---

### Task 1: 分类规则与样例准确性

**Files:**
- Modify: `config/v2-product-classification.json`
- Modify: `tests/BestSellersDataSemantics.Tests.ps1`

1. 先加入 PRD 指定的整机、surface cleaner、foam cannon/gun、hose、nozzle、chemical/pump protector 与模糊标题测试。
2. 运行 Pester，确认新增样例失败。
3. 以强配件优先、强整机其次、无安全命中为 unknown 的最小配置变更修复。
4. 重跑分类测试。

### Task 2: 共享 Machines Analytical Market 投影

**Files:**
- Modify: `web/lib/market-context.ts`
- Modify: `web/lib/ui-intelligence.ts`
- Test: `web/tests/market-context.test.mjs`
- Test: `web/tests/ui-intelligence.test.mjs`

1. 新增失败测试：当前/上一日、movers、entries/exits、品牌分母全部只保留整机。
2. 实现不可变投影函数，保持 raw observations 完整。
3. 新增分类覆盖、Unknown 计数与 verified machine count。
4. 运行目标测试。

### Task 3: 统一信号、产品名与格式化

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/components/ProductIdentity.tsx`
- Modify: `web/app/components/SignalCard.tsx`
- Modify: `web/app/components/ShellNavigation.tsx`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

1. 测试 High/Watch/Activity 明确分组且普通事件不计入重要信号。
2. 统一短名、价格、优惠、日期、评论数格式。
3. Signal 与 Activity 使用共享产品身份语义，不再只显示 ASIN/长标题。
4. 重跑目标测试。

### Task 4: 首页、产品与榜单语义收口

**Files:**
- Modify: `web/app/page.tsx`
- Modify: `web/app/products/page.tsx`
- Modify: `web/app/rankings/page.tsx`
- Modify: `web/app/rankings/RankingExplorer.tsx`
- Test: `web/tests/rendered-html.test.mjs`

1. 新增渲染测试：整机首页不出现配件；产品页只显示整机；榜单明确标记 Amazon 原始榜单且保留配件。
2. 页面接入共享投影。
3. 首页动态摘要只统计 High/Watch，普通事件单独引导。
4. 验证 raw 排名与 analytical products 同时正确。

### Task 5: 品牌结构与集中度

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/brands/page.tsx`
- Modify: `web/app/page.tsx`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

1. 先测 Top5 + Others、Seat Share、Top3 concentration 与 Unknown 处理。
2. 实现单一品牌结构函数，所有分母使用 Machines Analytical Market。
3. 品牌页展示 Top5 + Others、席位占比和口径提示。
4. 首页复用同一集中度结果。

### Task 6: Market Intelligence 多视图

**Files:**
- Modify: `web/app/market/page.tsx`
- Add: `web/app/market/MarketExplorer.tsx`
- Modify: `web/app/v2.css`
- Test: `web/tests/rendered-html.test.mjs`

1. 测试 Overview/Movers/Entrants/Brands/Price tabs 与 1D/3D/7D/30D 控件。
2. 实现默认 7D 的客户端视图；无足够历史时明确显示可用基线，不伪造数据。
3. 将 Movers（同一商品排名变化）与 Event Feed（入榜/出榜/价格事件）分区。
4. 保持已有状态指标和证据门槛。

### Task 7: Alerts、Data Status 与 Methodology

**Files:**
- Modify: `web/app/analysis/page.tsx`
- Modify: `web/app/insights/page.tsx`
- Modify: `web/app/methodology/page.tsx`
- Modify: `web/app/components/ShellNavigation.tsx`
- Test: `web/tests/rendered-html.test.mjs`
- Test: `web/tests/ui-accessibility.test.mjs`

1. 预警入口提供 High/Watch/All 紧凑语义，证据细节折叠。
2. Data Status 加分类覆盖率、Unknown 与已验证整机数量。
3. Methodology 补充 Seat Share、Classification Coverage、Movers/Event Feed。
4. 检查键盘、焦点、可访问名称与非颜色表达。

### Task 8: 全量验证、截图 QA 与发布

**Files:**
- Modify: `docs/audits/V2-FINAL-OPTIMIZATION-SCREENSHOT-QA-2026-08-31.md`

1. 运行 Pester/Node 全量测试与生产构建。
2. 启动本地站点，检查首页、市场、产品、产品详情、品牌、榜单、报告、数据状态。
3. 截图 1366×768、1440×900、1920×1080；检查层级、溢出、首屏、表格、对比度。
4. 修复发现的问题并重跑验证。
5. 请求代码审查，处理 Important 以上问题。
6. 使用既有 Sites 项目公开部署并做线上烟雾测试。
