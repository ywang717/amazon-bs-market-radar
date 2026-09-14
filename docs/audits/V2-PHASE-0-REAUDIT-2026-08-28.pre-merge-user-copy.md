# Amazon BS Market Radar V2.0 — Phase 0 Re-Audit Report

- 复核日期：2026-08-28
- 对照基线：`Amazon BS Market Radar V2.0 Final PRD`
- 复核范围：当前 `main`、网站子仓库、PostgreSQL/D1 schema、采集与发布链路、自动化测试、2026-08-27 线上数据
- 执行边界：本轮只复核，不修改 Schema、业务代码、Crawler、UI 或线上数据

## Executive Decision

**结论：V2.0 尚未完成。**

当前项目已经完成稳定的采集、回执、有效市场日、产品分类元数据、Raw/Analytical 分层、数据库同步和基础 Seller Intelligence；但按 PRD 的 Phase 1–10 验收，只有 Phase 1 的技术基础大部分落地，且 Brand 实际数据仍为 0。Phase 2–10 大多未开始或只有旧能力可复用。

最重要的遗漏不是 Crawler，而是：

1. 没有统一 V2 Intelligence Engine；
2. 没有品牌真实数据，品牌页无法可靠实现；
3. Market Context 只进入 API，没有进入核心 UI 和跨页继承；
4. 首页仍是旧的 Data Readiness Dashboard，不是 Signal-first 首页；
5. 市场、Compare、品牌、Alerts、Data Status 页面缺失；
6. 产品列表、产品详情、Timeline、Review Momentum 仅有很小一部分；
7. Design System Foundation、深色主题、共享业务组件、响应式与无障碍 QA 未完成；
8. Daily/Weekly 报告仍未统一消费 V2 Intelligence Engine；
9. 没有 Screenshot QA 或 Visual Regression；
10. 独立 PostgreSQL 健康检查仍硬编码 15 个视图，而当前 schema 已有 16 个。

## Fresh Verification Evidence

| 验证项 | 本次结果 |
| --- | --- |
| Windows PowerShell/Pester | 320 passed，0 failed |
| Python collector unittest | 80 passed，0 failed，0 skipped（使用项目 `.venv`，含 Playwright DOM 用例） |
| Web tests | 第一阶段 79 passed；构建后 94 passed；合计 173 passed，0 failed |
| Web production build | 成功 |
| ESLint + jsx-a11y | 成功 |
| 线上市场日 | 2026-08-27 |
| 线上 Pressure Washers Raw | 30 |
| 线上 Pressure Washers / Machines Analytical | 10 |
| 完整市场日 | 15 |
| PostgreSQL 快照 | 15 个市场日，每日 90 条；2026-08-19 正确缺失 |
| Product metadata | 131 ASIN；59 已分类；72 unknown |
| Brand metadata | 131 个全部 `brand_source=unknown`；真实品牌覆盖 0 |

说明：用 PowerShell 7 跑同一 Pester 集合会出现 3 个运行时兼容失败；项目目标 Windows PowerShell 5.1 的完整运行为 320/0，因此不把这 3 项误判为产品回归。

# 1. Current Architecture

## Local runtime

- Windows PowerShell orchestration + Python collector + PostgreSQL 18；
- 采集、回执、导入、报告、备份、健康检查、网站发布相互设门；
- `db/migrations/001`–`012`，当前 Amazon Intelligence schema 有 16 个 view；
- 日度主链路能生成 3 个类目各 Top30、报告、备份和发布状态。

## Website

- vinext/React/TypeScript/Vite；
- D1 保存快照、观测、报告元数据和 product metadata；R2 保存 PDF；
- 公开读取 API 与 Bearer-secret 同步 API 分离；
- 当前构建含首页、7 个页面路由和 15 个 API 路由。

## Operational state

- 2026-08-27 已公开发布，90 条观测、3 份 PDF；
- 线上 API 能区分 Raw Ranking 与 Pressure Washers / Machines Analytical Market；
- `main` 与网站发布源已包含 Phase 1 数据语义提交。

# 2. Existing Capabilities

## Already exists and should be reused

- Amazon US 三个独立榜单精确 Top30 采集；
- 失败、部分、缺失快照不冒充有效市场日；
- Receipt + SHA-256 + source metadata 绑定；
- `null` 保真、价格/评分/评论字段覆盖率；
- 日度排名比较、Top10 Entry/Exit、Top30 Entry/Exit、Discount change；
- 日报、周报、PDF、网站报告归档；
- PostgreSQL/D1 双端版本化同步；
- Product Classification 配置、规则版本、置信度与 evidence；
- Raw Brand / Normalized Brand 字段和 alias 规则机制；
- 有效市场日选择器；
- Raw Ranking 与 Analytical Market API 分层；
- Seller Intelligence 的日度信号与周度事实框架。

## Exists but is not organized as V2

- First seen date 已写入 metadata，但未形成 V2 Entrants UI；
- Daily rank move 已有，但没有 1D/3D/7D/30D 统一时间窗；
- Top10 stability 已有相邻日事实，但没有 Market Volatility/Turnover 聚合；
- competitor pool 有 `daysPresent`，但不是统一 Top30/Top10 Presence；
- Seller signal card 是页面内部实现，不是共享 `SignalCard`；
- Data quality 信息很强，但仍占据首页核心，而不是右上 Data Status。

# 3. Existing Schema

## PostgreSQL

当前包含两组模型：

1. 通用规范化模型：marketplace/category/product/brand/ranking/offer/listing/review/signals；
2. 当前 Best Sellers 主链路：run/source_run/observation/daily views/analysis tables/product metadata。

Migration 012 已增加：

- `best_sellers_product_metadata`；
- `product_type`；
- `classification_confidence`；
- classification rule/version/evidence；
- `raw_brand` / `normalized_brand` / `normalized_brand_key`；
- brand source/alias rule；
- first/last seen market date；
- `best_sellers_valid_category_day`。

## D1

- `product_metadata` 维度表已存在；
- sync bundle v2 强制 metadata cohort 与 observation ASIN 集合一致；
- metadata 与 snapshot 在一个 batch 中写入；
- raw ranking observation 没有被 product type 过滤。

## Actual data coverage

- 131 个 ASIN 中 59 个得到具体 product type，72 个为 unknown；
- 规则主要覆盖 Pressure Washers 与配件，Sump Pumps 尚无 V2 product type；
- 131 个 ASIN 的品牌均为 unknown；Brand schema 已有，但业务数据不可用。

# 4. Existing Analysis Logic

## Reusable

- `compareRankings` 的方向正确：旧 rank - 新 rank，数字越小表示上涨；
- exact Top30 validator；
- valid category-day selector；
- field coverage/evidence gates；
- Seller daily signals：rank move、Top10 entry/exit、Top30 entry/exit、discount change；
- weekly net movement、large swing、entry/exit 和 discount transition；
- price band、rank influence、market structure 等旧分析可保留为旁路资产。

## Not yet V2 compliant

- Signal priority 仍有 high/medium/low 等旧语义，没有统一为 High/Watch/Market Activity；
- 阈值分散在多个 PowerShell 模块和页面；
- 没有统一 3D/7D/30D 有效市场日窗口；
- 没有 First Seen/New Entry/Re-entry/Exit 完整状态机；
- 没有 Rising/Strong Rising/Falling 统一规则；
- 没有 Top30/Top10 Presence、consecutive days 和 Rank Stability 统一算法；
- 没有 Review 7D/30D Growth、Velocity、Momentum；
- 没有 7D Turnover、Brand Concentration、Brand Expansion；
- 没有 Market Volatility Low/Medium/High；
- 报告、本地 Seller Intelligence、网站 dashboard 仍存在多套计算路径。

# 5. Existing UI Architecture

当前页面：

- `/` 总览；
- `/rankings` 榜单；
- `/products` 产品趋势；
- `/products/[asin]` 产品详情；
- `/insights` 洞察；
- `/analysis` 智能报告/卖家分析；
- `/reports` 报告；
- `/methodology` 方法说明。

当前一级导航仍是：

> 总览｜榜单｜产品趋势｜洞察｜卖家分析｜智能报告｜报告｜方法说明

PRD 导航：

> 总览｜市场｜产品｜品牌｜榜单｜报告 + Alerts + Data Status

因此 UI information architecture 尚未进入 V2。

# 6. Existing Design Tokens

现有 CSS 有少量全局变量：nav、ink、muted、line、bg、blue、green、amber、red、panel；容器宽度 1420px，主要圆角 7–14px，已有少量 1050/650 响应式规则。

关键差距：

- 当前实际是浅色页面 + 深色顶部栏，不是 PRD 所述 Dark Theme；
- 没有 Level 0–3 surface tokens；
- 没有统一 semantic status token 和 typography/spacing/radius scale；
- 没有 `font-variant-numeric: tabular-nums`；
- 全局 focus-visible 未建立；
- CSS 高度压缩、`globals.css` 与 `enhancements.css` 并存，维护成本较高。

# 7. Reusable Components

正式共享组件只有：

- `SiteShell`；
- `PageHeader`；
- `QualityBadge`。

可提取复用但目前仍内联：

- Seller signal card；
- Seller empty state；
- ranking delta 文案；
- product history chart point；
- tabs/filter controls；
- report archive row；
- data quality/status presentation。

# 8. Duplicate Components

存在语义重复而非文件名重复：

- Rank 在首页、榜单、产品页、Seller Intelligence 各自格式化；
- Entry/Exit 与 movement 在 PowerShell、web analytics、report generator 各自表达；
- badges 由 `QualityBadge`、Seller priority 文案和页面 class 混用；
- empty state 在多个页面内联；
- tabs 在 Ranking Explorer 与 Analysis workspace 采用不同实现；
- evidence/coverage 信息在首页、产品、analysis 页面分别排版；
- 信号计算与展示没有共享 contract + shared component 的完整闭环。

# 9. Existing Chart System

- 无通用 chart library；
- 产品详情使用 CSS absolute-position points；
- Rank #1 视觉位置在顶部，方向正确；
- quality timeline、progress、score ring 都是独立 CSS；
- 没有统一 Tooltip、Axis、Grid、Event marker、时间窗；
- 没有 Compare Rank Chart；
- product history 主要依赖 `title` hover，不满足键盘/触屏等价访问；
- 没有视觉回归测试。

# 10. V2 Requirement → Existing Capability Mapping

| V2 能力 | 状态 | 结论 |
| --- | --- | --- |
| Market Context data contract | Partially Exists | API 支持 US/category/segment；UI 无统一 selector，跨页不继承 |
| Raw Ranking | Already Exists / Reuse | `/rankings` 保留原始 Top30，语义正确 |
| Analytical Market | Partially Exists | overview API 可过滤；没有市场页面和主 UI 消费 |
| Product Classification | Partially Exists | 规则、存储、同步、测试完成；真实覆盖 59/131，其它 72 unknown |
| Brand Normalization mechanism | Already Exists | schema/config/tests 已有 |
| Brand data | Missing | 131/131 均 unknown，品牌业务功能当前不可上线 |
| First Seen | Partially Exists | metadata 日期存在，未进入状态机/UI |
| New Entry / Exit | Partially Exists | 相邻有效日已有基础；未统一到 V2 Engine |
| Re-entry | Missing | 无可靠状态机和 UI |
| Missing Data discipline | Already Exists / Reuse | 当前项目最成熟能力之一 |
| 1D trend | Partially Exists | 日比较存在 |
| 3D/7D/30D trend | Missing | 周报净变化不等于统一窗口 API |
| Rising/Strong Rising/Falling | Missing | 没有 PRD 规则实现 |
| Presence/Stability | Partially Exists | daysPresent/Top10 stability 可复用；V2 指标未实现 |
| Review Growth/Velocity/Momentum | Missing | 历史字段有，算法/API/UI/测试无 |
| Turnover | Partially Exists | entry/exit 事实有，7D 聚合与等级无 |
| Brand concentration/expansion | Missing | 无品牌数据和统一算法 |
| Market volatility | Missing | 无明确算法、方法说明、测试 |
| Signal system | Partially Exists / Refactor | Seller signals 可迁移；类型、优先级、阈值、Evidence 未统一 |
| Overview V2 | Missing | 线上仍显示“分析就绪状态”和 99/100 readiness |
| Market page | Missing | 无 route |
| Products list | Missing | 当前仅三个榜首 card，无 search/sort/filter/table |
| Product detail | Partially Exists | 当前/最佳/在榜天数/历史点；缺完整 ranking/presence/review/timeline |
| Product Compare | Missing | 无 route/API/UI |
| Brand list/detail | Missing | 无 route/API/UI |
| Alerts | Partially Exists | 卖家分析有预警工作区；无右上入口、High/Watch 面板与 activity 分层 |
| Data Status | Missing | 质量信息存在但没有右上入口/独立面板 |
| Daily Brief | Partially Exists / Reuse | 有日报与 seller alert；未消费统一 V2 Engine |
| Weekly Report | Partially Exists / Reuse | 有周报链路；内容和算法未完成 V2 统一 |
| Design System Foundation | Missing | 只有 3 个共享组件和少量旧 tokens |
| Responsive baseline | Partially Exists | 有两档 CSS；1050px 以下导航直接隐藏且无替代 |
| Accessibility baseline | Partially Exists | jsx-a11y lint 可用；缺全局 focus、完整 tabs、chart/touch tooltip |
| Screenshot QA | Missing | 无 1366/1440/1920 证据 |
| Visual Regression | Missing | 测试栈无对应资产 |

# 11. Actual Missing Capabilities

按依赖顺序，真正阻塞 V2 的缺口是：

1. 可验证 Brand 来源与品牌回填；
2. 统一 Intelligence Engine 与阈值配置；
3. Entry/Re-entry 状态机和有效日窗口；
4. 3D/7D/30D Trend、Presence、Stability、Review、Turnover、Volatility、Brand 指标；
5. V2 Signal schema：High/Watch/Market Activity + Evidence；
6. MarketContext UI/URL 继承；
7. Signal-first Overview；
8. Market、Products、Compare、Brands、Alerts、Data Status 产品面；
9. V2 Daily/Weekly report composition；
10. Design System、responsive、accessibility、screenshot QA。

# 12. Schema Changes Actually Required

Phase 1 已完成最小 product metadata schema，因此不建议再次新增重复产品维度。

仍需决定：

- Brand verified metadata 的来源、回填流程和 provenance；
- 是否需要 brand dimension/key，或现有 normalized brand key 足以支撑首版；
- Signal 是否动态生成（建议）而不是立刻持久化；
- event timeline 是否动态从观测/discount 推导（建议）；
- classifier 规则升级如何保留 rule version 并可审计重算。

不建议持久化：3D/7D/30D、Presence、Stability、Review Velocity、Turnover、Volatility、Signal Priority，除非性能数据证明需要 cache/materialization。

# 13. API Changes Actually Required

缺少或需扩展：

- market summary/movers/entrants/brands/price；
- products list 的 search/filter/sort/pagination；
- product detail 的多窗口、presence、review、timeline；
- compare 2–5 ASIN；
- brands list/detail；
- alerts High/Watch/activity；
- data status；
- V2 overview summary + Top5 Signals；
- 所有核心 API 统一 context/date/window contract。

现有 `/api/public/rankings` 应继续保持 Raw，不应改成 Analytical。

# 14. UI Changes Actually Required

- 导航收敛为 PRD 六项；
- 增加右上 Alerts/Data Status；
- Market Context breadcrumb + selector；
- 首页移除 readiness score 的主视觉地位，改为 Top Signals；
- 增加 Market 五个 tabs；
- Products 改为统一高密度表格；
- Product Detail 增加完整指标、时间窗和事件 Timeline；
- 新增 Compare、Brands、Brand Detail、Alerts、Data Status；
- 报告中心只突出 Daily Brief 与 Weekly Report；
- 建共享 Rank/Product/Badge/Signal/Tooltip/EmptyState 组件后再迁移页面。

# 15. Migration Risks

1. **品牌数据风险最高**：schema 存在但真实覆盖为 0；不能用标题猜品牌。
2. **双计算路径漂移**：PowerShell、web analytics、Seller reports 仍可得出不同口径。
3. **双数据库演进**：PostgreSQL 与 D1 contract 必须同步升级。
4. **历史 classifier 重算**：规则版本更新会改变 Analytical Market。
5. **旧报告不可变键**：V2 报告 schema 应版本化，不能原地改变已归档语义。
6. **seed fallback**：普通 dashboard 仍可回退旧 seed；V2 今日信号不得使用陈旧 seed 冒充实时。
7. **全表读取性能**：overview/product loader 仍读取大量全量记录，历史增长后会线性变慢。
8. **工作区卫生**：`.worktrees` 下有多个已失去 Git metadata 的旧目录；另有一个注册 worktree 带未跟踪临时内容，后续应人工确认后清理，不能自动删除。
9. **健康检查漂移**：`Test-LocalPostgres.ps1` 仍断言 15 views，实际为 16。

# 16. Test Gaps

已覆盖：classification、brand normalization contract、valid market days、raw/analytical separation、metadata sync、缺失数据、现有 daily signals、构建和 lint。

未覆盖 PRD 核心：

- First Seen/New Entry/Re-entry/Exit 完整状态机；
- 1D/3D/7D/30D 有效日窗口；
- Rising/Strong Rising/Falling；
- Top30/Top10 Presence、consecutive days、Rank Stability；
- Review 7D/30D growth/velocity/momentum；
- Brand seats/share/expansion/concentration；
- 7D turnover、新入频率、volatility；
- High/Watch/Market Activity；
- Price × Rank 同期事件与非因果文案；
- Compare 2–5 产品与统一时间轴；
- 1366×768、1440×900、1920×1080 screenshot QA；
- mobile navigation、keyboard tabs、tooltip、focus order；
- visual regression。

测试入口说明：Python 用例基于标准库 `unittest`，不是 `pytest`。项目 `.venv` 已能运行全部 80 个用例，包括 Playwright DOM 解析用例；初始化文档和验证命令应明确使用正确入口，避免把未安装的 `pytest` 误判为测试环境失败。

# 17. Accessibility Issues

- 1050px 以下主导航直接 `display:none`，没有 menu 替代；
- 主导航没有 active route/`aria-current`；
- Ranking tabs 有 `role=tab` 和 `aria-selected`，但缺 `aria-controls`、tabpanel 关联和 arrow-key 行为；
- 产品 rank chart 点依赖 hover/title，键盘与触屏不可等价访问；
- 只有 Seller 区域有明确 focus-visible，未覆盖全站；
- table 缺 caption/scope 统一策略；
- loading 仍以文字为主，没有统一 skeleton/aria-busy；
- 状态表达大多有文字，但 progress/score ring/status dot 仍有视觉依赖。

# 18. Highest Impact UI Improvements

1. 首页改为 Top5 Signals，Data Quality 移到右上 Data Status；
2. 建 MarketContext 并贯穿总览/市场/产品/品牌/报告；
3. 建统一 RankDisplay/RankDelta/ProductIdentity/SignalCard；
4. 建 Products 表格和 Product Detail Timeline；
5. 增加 Market 页面，让 Analytical Market 不只存在于 API；
6. 修复移动导航和全局 focus-visible；
7. 明确选择 Dark V2 迁移，而不是把当前浅色 UI 误认为已有 Dark Theme。

# 19. Recommended Implementation Plan

## Gate 0 — 补齐 Phase 1 的业务可用性

1. 确认 verified Brand 来源；
2. 回填品牌并输出覆盖率；
3. 将 MarketContext 写入 URL/UI，保证跨页继承；
4. 明确 Sump Pumps 首版是否只支持 `all_bestsellers + unknown product_type`。

## Phase 2 — Unified Intelligence Engine

按 PRD 顺序实现纯函数与参数化测试：event state machine → windows/trend → presence/stability/review → market/brand → signal。统一阈值配置，旧 Seller Intelligence 作为 adapter，不再继续增加第三套算法。

## Phase 3–4 — Design Foundation + Overview/Market

先完成 tokens 和共享组件，再把 Overview 做成视觉样板；通过 1366/1440/1920 与 keyboard QA 后再实现 Market。

## Phase 5–9 — Vertical slices

Products → Product Detail/Timeline → Compare → Brands → Alerts → Reports。每个页面只消费统一 Engine/API。

## Phase 10 — Cleanup & QA

最后处理旧 routes、重复 CSS、seed fallback、performance cache、responsive、accessibility、visual regression 和旧 worktree 清理。

# 20. Files Likely To Change

## Data/engine

- `config/v2-brand-aliases.json`
- 新增统一 intelligence thresholds/config
- `src/BestSellersDataSemantics.psm1`
- `src/SellerIntelligence.psm1`（改为 adapter/facade）
- 新增 V2 Intelligence 模块与测试
- 可能新增 PostgreSQL/D1 migration，但不重复创建 product metadata

## Website data/API

- `web/lib/market-context.ts`
- `web/lib/valid-market-days.ts`
- `web/lib/analytics.ts`
- `web/lib/live-dashboard-data.ts`
- 新增 intelligence 子模块
- 扩展 overview/products API
- 新增 market/compare/brands/alerts/data-status API

## Website UI

- `web/app/components/SiteShell.tsx`
- `web/app/page.tsx`
- `web/app/products/*`
- `web/app/rankings/*`
- 新增 market/compare/brands/alerts/data-status routes
- 新增 PRD 第 93 节共享组件
- `web/app/globals.css`
- `web/app/enhancements.css`（迁移后收敛）

## Tests/operations

- Pester V2 engine tests
- Web engine/API/rendered HTML tests
- screenshot/visual regression/a11y tests
- `scripts/postgres/Test-LocalPostgres.ps1` 的 view count 断言
- runtime manifest/初始化流程，保证 Python test dependencies 可重复安装

# Scope Reduction Suggestions

| 需求 | 建议 | 原因 |
| --- | --- | --- |
| Crawler | 保留/复用 | 当前不是阻塞项，已有严格回执与 Missing Data 保护 |
| Raw Ranking | 保留/复用 | 已完整存在，只需统一 UI 组件 |
| Market Context | 保留/简化 | 首版 US；Pressure Washers 完整 segment；其它类目只 All Bestseller |
| Product Classification | 保留/补覆盖 | 框架已完成，不做 ML；unknown 是合法结果 |
| Brand Normalization | 保留，但先补数据 | 机制已有；无 verified brand 时品牌功能没有业务价值 |
| First Seen/Entry/Re-entry | 保留 | 是 V2 变化情报基础 |
| 3D/7D/30D | 保留/简化 | 只用有效市场日净变化与上涨比例，不做 Momentum Score |
| Presence/Stability | 保留/简化 | 首版做 Top30/Top10/consecutive + 可解释分级 |
| Review Momentum | 保留/简化 | 只描述评论增长速度，不推断销量 |
| Brand Intelligence | 保留但设置数据门 | Brand coverage 未达门槛时显示 unavailable，不展示伪品牌分析 |
| Turnover/Volatility | 保留/简化 | 使用 PRD 明确的四类事实，不做 0–100 分数 |
| Signal Engine | 复用/重构 | 从 Seller signals 迁移，不新建并行引擎 |
| Overview | 保留/重构 | Signal-first 是 V2 最大产品价值 |
| Market | 保留 | 是 Analytical Market 的主要承载面 |
| Products | 保留/简化 | 一张表 + 一个详情，不做卡片海洋 |
| Compare | 保留/简化 | 2–5 产品、一个 Rank Chart、一张表 |
| Brands | 保留/延后到品牌覆盖达标 | 页面代码不应先于可靠数据 |
| Alerts | 复用/重构 | 使用现有 seller alerts，拆 High/Watch/Activity；不做通知订阅 |
| Reports | 复用/重组 | 保留 PDF、归档、发布链路，只替换内容来源 |
| Dark Theme | 保留目标但渐进迁移 | 当前不是 Dark；必须先做 tokens，再逐页迁移 |
| Product images | 延后或允许 placeholder | 当前无可信图片字段，不能伪造 |
| 90D Timeline | 简化 | 当前只有 15 个有效市场日；支持控件，但明确样本不足 |
| Visual Regression | 保留 | 页面迁移后价值高；在 Overview 样板确认后加入 |
| Opportunity/Market Score | 从 V2 UI 删除 | 与 PRD 禁止黑盒分数原则冲突，历史代码可保留 |
| Accounts/Watchlist/AI/Sales estimates | 延后 V2.1+ | 明确超出范围 |

## Final Re-Audit Decision

**不建议把当前状态标记为“V2 完成”。**

可以确认：Phase 1 的代码基础已大部分完成并通过测试，但必须先补齐 Brand 数据来源与 MarketContext UI，随后进入统一 Intelligence Engine。当前不应直接跳到大规模 UI 开发，也不应重写 Crawler。

本次 Re-Audit 到此停止，等待人工确认下一阶段。
