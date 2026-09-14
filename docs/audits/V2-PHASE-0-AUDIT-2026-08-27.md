# Amazon BS Market Radar V2.0 — Phase 0 Audit Report

- 审计日期：2026-08-27
- 审计范围：仓库代码、迁移、测试、仓库内历史样本，以及本机 `var/` 中的实际运行产物
- 本轮边界：只执行 Phase 0；未修改 Schema、Crawler、Analysis Engine、导航或 UI
- 核心结论：现有项目已具备可靠的采集、完整性校验、历史保存、日报/周报、网站同步和一套可复用的日度 Seller Signal 基础。V2 应采用“保留采集与运行链路、统一语义与分析层、渐进替换页面”的升级路径，不应重写项目。

## Executive Summary

当前系统已经不是简单原型，而是一个由本地运行面和网站展示面组成的完整流水线：Windows/PowerShell/Python/PostgreSQL 负责采集、回执、历史、报告、备份和发布；vinext/React/D1/R2 负责接收已验证数据并提供只读网站与 PDF/JSON 归档。

V2 可直接复用的核心资产包括：

- 三个 Amazon US Best Sellers Top30 榜单采集与精确完整性校验；
- `null` 保真、字段覆盖率门槛、失败日保留但不生成快照的 Missing Data 纪律；
- 排名方向正确的日度比较、Top10 留存、Top30 进出、优惠变化；
- Seller Intelligence 的日度信号、周度竞争事实、证据边界与不可变归档；
- PostgreSQL 追加式历史、D1 同步契约、回执哈希与幂等/原子写入；
- 日报、周报、在线分析报告和 PDF 归档。

V2 的主要缺口不是采集，而是：

1. 当前 Best Sellers 主链路没有可验证 Brand 字段，也没有统一 Machine/Accessory 产品类型；
2. “有效市场日”在本地报告、PostgreSQL 视图、网站实时比较和产品历史中存在不同实现；
3. 现有信号只覆盖日度 Rank/Top10/Top30/Discount，且严重度是 high/medium/low，不等于 V2 的 High/Watch；
4. 没有统一 Market Context、Analytical Market、品牌页、Compare、专门 Alerts、Data Status；
5. 首页仍以 Data Quality/Readiness 为视觉中心，产品页只展示三个榜首，和 V2 的 Signal-first 目标差距较大；
6. 网站在 D1 异常时使用 2026-08-12 的仓库内 seed 数据继续计算页面指标，虽有提示但仍有“陈旧数据被当作当前工作面”的产品风险；
7. V2 指定的趋势、Presence、Review、Brand、Turnover、Volatility 算法尚无统一实现和测试。

建议先建立一个纯函数、配置化、跨页面复用的 Intelligence Layer，并把 Raw Ranking 与 Analytical Market 严格分开；所有 V2 派生指标先动态计算，只有真实性能证据出现后再缓存或物化。

## 1. Current Architecture

### 本地运行面

- 入口：`Start-Amazon-BS.bat` → `scripts/Start-LocalPackage.ps1` → `src/LocalPackageOrchestrator.psm1`。
- 采集：`scripts/python/collect_best_sellers.py` 通过可见浏览器采集三个公开 Best Sellers 榜单；PowerShell 包装器负责运行、错误边界和机器可读状态。
- 运行环境：项目内 `.venv/`、`.local/python/`、`.local/postgresql/`，避免依赖机器全局环境。
- 主数据库：PostgreSQL，迁移位于 `db/migrations/001`–`011`。
- 报告：PowerShell 生成 Markdown/HTML，项目 Python 生成并验证 PDF。
- 调度：Windows Scheduled Tasks，日常采集、周报、网站发布和发布恢复分别调度。

### 网站展示面

- 框架：vinext 1.0 beta、React 19、TypeScript 5.9、Vite 8。
- 数据库：Cloudflare D1/SQLite，通过 Drizzle Schema 和 SQL migration 管理。
- 文件：R2 保存 PDF；D1 保存快照、观测、报告元数据和分析 JSON。
- 页面：Server Components 为主，交互式榜单、报告和分析中心使用 Client Components。
- 部署：Cloudflare/Sites 形态，网站公开 API 为只读，写入仅通过 Bearer Secret 保护的同步 API。

### 重要架构边界

PostgreSQL 中同时存在两套模型：

- `001`–`006` 的规范化通用情报模型（marketplace/category/product/brand/ranking/offer/listing/metrics/signals）；
- `007`–`011` 为当前实际 Best Sellers 流程新增的 denormalized 历史表与分析表。

当前 Best Sellers 浏览器主链路主要落在第二套模型，未把 ASIN 连接到第一套 `product`/`brand` 维度。因此“数据库已有 brand/product/first_seen 表”不等于当前 Best Sellers 数据已经拥有这些可用字段。

## 2. Current Data Flow

日常主链路：

1. 可见浏览器按配置采集三个榜单 Top30；
2. 采集器写 `amazon-bestsellers.json` 和 collection status；
3. 回执模块核对市场日、来源节点、内容 SHA-256、30 个唯一 ASIN 与连续排名；
4. 仅验证通过的快照事务导入 PostgreSQL；
5. 生成三个榜单日报及 PDF，记录邮件结果；
6. 生成/验证数据库备份和日常健康状态；
7. 独立网站发布任务在健康门通过后生成 Dashboard Sync Bundle；
8. Bundle 原子同步到 D1；日报 PDF 同步到 R2；
9. 生成并同步 4 份日度在线分析报告和 4 份 Seller Alert；有匹配周报时额外同步 Weekly Analysis 与 Competition Strategy；
10. 网站从 D1 动态加载最新数据；D1 异常或为空时退回仓库内 seed history。

本地实际运行证据：

- `var/amazon-bestsellers/` 包含 2026-08-12 至 2026-08-26 的运行目录；
- 2026-08-19 是明确失败日：0 条观测、无快照、保留失败 status；
- 其余 14 个目录有 `COMPLETE_VALIDATED` 回执，均为三个榜单各 30 条；
- 2026-08-26 三个榜单 Price/Rating/Reviews 覆盖均为 30/30，Discount state 也为 30/30；
- 2026-08-16 配件榜 Rating/Reviews 为 29/30，但排名与 ASIN 完整，因此市场日仍可用于排名分析，字段分析应单独受覆盖率门槛控制；
- 本地已有 86 份 HTML、86 份 Markdown、78 份 PDF、54 份 JSON 报告产物；
- Seller Intelligence 本地归档当前有 2026-08-25 与 2026-08-26 两个日度 cohort（每个 4 份）。

## 3. Existing Schema

### PostgreSQL 通用规范化模型

主要表：

- 市场与来源：`marketplace`、`category`、`category_source_map`、`source_definition`；
- 主数据：`brand`、`brand_alias`、`seller`、`product`、`product_category`；
- 采集与证据：`collection_run`、`raw_artifact`、`data_quality_issue`；
- 历史事实：`ranking_observation`、`offer_snapshot`、`listing_snapshot`、`listing_content_snapshot`、`review_snapshot`；
- 派生层：`daily_product_metric`、`daily_brand_metric`、`detection_signal`、`opportunity_score`。

### PostgreSQL 当前 Best Sellers 主模型

- `best_sellers_run`：市场日、采集时间、快照路径/哈希、目标数、来源数；
- `best_sellers_source_run`：每个 category 的 item/ASIN/rank 计数和 `quality_passed`；
- `best_sellers_observation`：category、market_date、ASIN、rank、title、URL、price、rating、review_count、discount；
- `best_sellers_analysis_run` / `best_sellers_opportunity_signal`：旧机会分析；
- `best_sellers_market_structure_run` / price band / accessory classification；
- `best_sellers_rank_influence_run` / association / bucket；
- 多个 current/change/exit/latest views。

### 网站 D1 模型

- `snapshots`；
- `category_days`；
- `observations`；
- `observation_discounts`；
- `reports`；
- `analysis_reports`；
- `seller_intelligence_reports`。

D1 目前没有 Product Dimension、Brand、Classification、Market Segment 或持久化 Signal 表。

## 4. Existing Data Fields

### 当前 Best Sellers 原始快照

- 市场级：`schema_version`、`marketplace`、`market_date`、`observed_at`、`sources`；
- 观测级：`rank`、`asin`、`title`、`url`、`price`、`rating`、`reviews`、`has_discount`、`discounts`；
- 回执/状态：category key、node、source URL、target/item/unique counts、missing/duplicate/out-of-range ranks、完整性、快照哈希。

### 已存在但未接入当前 Best Sellers 主链路的字段

- 通用 canonical observation 支持 `brand_raw`、model、seller、offer/listing 字段；
- 通用 `product` 有 `first_seen_at`、`last_seen_at`；
- 通用 `brand`/`brand_alias` 支持 canonical name 与 alias；
- `daily_product_metric` 预留 review velocity；
- 当前 Best Sellers 快照与 D1 observation 均没有 brand、product_type 或 classification confidence。

### 数据真实性现状

- 缺失 Price/Rating/Reviews 保留 `null`；
- Discount 使用 true/false/null 三态和结构化事件；
- 网站同步把显示价格字符串规范为数值，但不编造缺失值；
- 当前没有 Sales、Revenue 或 Market Share 字段，符合 V2 禁止范围。

## 5. Existing Analytics

已存在且可复用：

- Exact Top30 校验：30 条、rank 1–30 连续、30 个唯一 ASIN；
- Field Coverage：Price/Rating/Reviews 低于 80% 时暂停相关描述；
- 日度 Rank Delta：`previous rank - current rank`，正值表示上升；
- 完整日之间的 movers、平均绝对位移、最大位移、Top10 retained、entries、exits、movement bands；
- 周度 net movement、最大日波动、进出榜、优惠转变；
- 价格带和标题规则的配件分类；
- Pearson/Spearman 的价格、评分、评论与排名描述性关联；
- Competitor Pool：days present、Top10 appearances、最大位移；
- Top10 stability、price bands、specification coverage；
- Evidence level 和分析 readiness。

不可直接作为 V2 定义复用：

- 旧 Opportunity Score/High Opportunity/Rank Influence 不符合 V2“不要复杂评分”的方向，应保留为 legacy，不进入 V2 核心 UI；
- 当前 `rankingConcentration` 是 Top10 名次权重占比，不是 Top3 Brand Concentration；
- 当前 product `daysListed` 只统计出现过的不同市场日，不是 Presence 分母，也没有过滤 category day 完整性；
- 当前网站日度比较只允许“紧邻前一个 snapshot 也完整”时计算，不会跳过失败日寻找上一有效市场日；本地 Seller Intelligence 则会筛完整历史后取最近两天，两边语义不一致；
- PostgreSQL `best_sellers_daily_exit` 未显式要求 current/previous `quality_passed`，存在不完整日被误判 Exit 的结构性风险；
- PostgreSQL `best_sellers_daily_change` 按 ASIN `lag()`，会跨缺失/退出间隔连接两次出现，不能区分连续在榜与 re-entry。

## 6. Existing Alert Logic

现有 Seller Intelligence 已具备 V2 Signal Engine 的雏形：

- `rank_move`：绝对变化 ≥10；10–19 为 medium，≥20 为 high；
- `top10_entry` / `top10_exit`：high；
- `top30_entry` / `top30_exit`：high；
- `discount_change`：两侧均可验证且状态变化时 high；
- 每条信号包含 ASIN、当前/上一排名、checks、evidence；
- 只有两份精确完整 Top30 才生成；排序按 priority、kind、ASIN；
- 本地报告和网站 live/contract 都有测试。

与 V2 的差距：

- 不是统一的 High/Watch，仅有 high/medium/low；
- 缺 Rank Surge/Drop 的方向化类型、Re-entry、Brand Expansion/Contraction、Price Increase/Drop、Coupon Added/Removed、Review Momentum；
- Top30 entry 当前一律 High，与 V2 推荐的“普通新入榜可为 Market Activity/Watch”不一致；
- 没有 market context、current/previous value 的通用字段、magnitude、confidence、deep link；
- 阈值散布在 PowerShell、本地报告 contract、网站 TypeScript 和测试中，尚未集中到一份 config；
- 页面没有独立 Alerts 入口/面板，信号主要藏在 `/analysis` 工作区。

实际 2026-08-26 Pressure Washers Seller Alert 有 5 条信号（4 high、1 medium），覆盖 rank move、Top10 entry/exit、Top30 entry/exit，证明现有链路可用于 V2 迁移验证。

## 7. Existing Report Logic

现有四类报告：

1. Best Sellers 日报：每个 category 独立生成 Markdown/HTML/PDF，可选邮件；仅在 current/previous 均完整时描述变化；
2. Best Sellers 周报：每个 category 独立 PDF，并生成周度 JSON 分析；包含净排名、日波动、进出、优惠变化与有限关联；
3. Online Analysis：daily/weekly × overview/3 categories 的 JSON，不可变归档，证据不足时只输出质量披露；
4. Seller Intelligence：daily seller_alert 与 weekly competition_strategy，均为 overview/3 categories cohort，带强 contract 验证。

优点：报告已具备证据门、缺失数据保护、原子同步、不可变 key、私密运营信息过滤和 PDF 验证。

问题：日报、周报、Online Analysis、Seller Intelligence 和网站实时页仍各自组合部分计算；V2 指标若继续分别添加会产生重复算法。V2 Daily Brief/Weekly Report 应改为同一 Intelligence Layer 的不同 presentation，而不是继续扩展多套规则。

## 8. Existing Pages

- `/`：市场情报总览，但核心是 Analysis Readiness/Data Quality；
- `/rankings`：三个 Raw Top30，支持 tab、关键词与 Top10/20/30 筛选；
- `/products`：仅展示三个榜单各自的 #1 产品，不是产品目录；
- `/products/[asin]`：产品当前事实、简单历史点图、标题可验证规格；
- `/insights`：证据阶梯、可用性矩阵、字段覆盖和方法卡；
- `/analysis`：实时/历史 Online Analysis，以及 Seller Alert、Competition Strategy、Archive 工作区；
- `/reports`：PDF 报告归档；
- `/methodology`：现有 Top30、完整度、证据与关联规则。

缺失页面：Market、Brand list/detail、Compare、独立 Alerts、Data Status。现有 Insights/Analysis 可作为迁移来源，但不等于 V2 Market/Alerts。

## 9. Existing Routes

### 页面路由

`/`、`/rankings`、`/products`、`/products/:asin`、`/insights`、`/analysis`、`/reports`、`/methodology`。

### Public API

- `/api/public/overview`；
- `/api/public/rankings`；
- `/api/public/products/:asin`；
- `/api/public/reports` 与 `/api/public/reports/:key+`；
- `/api/public/analysis`、`/live`、`/:key+`；
- `/api/public/seller-intelligence`、`/live`、`/:key+`。

### Sync API

- `/api/sync/v1/bundles`；
- `/api/sync/v1/reports`；
- `/api/sync/v1/analysis-reports`；
- `/api/sync/v1/seller-intelligence`。

路由输入对 category、date、ASIN 和 immutable key 有较完善校验；Market Context 目前没有统一 URL contract。

## 10. Existing Shared Components

现有真正共享的 UI 组件只有：

- `SiteShell`；
- `PageHeader`；
- `QualityBadge`。

业务复用主要仍靠页面内 JSX/CSS class。V2 推荐组件 MarketContext、MetricCard、SignalCard、RankDisplay、RankDelta、ProductIdentity、ProductTypeBadge、EvidenceBadge、AlertBadge、DataStatus、EmptyState、ChartTooltip、TimelineEvent、MarketStatusHeader 均不存在或未抽象。

## 11. Existing Design System

当前为浅色 UI：nav 深蓝，页面灰白，panel 白色，Blue/Green/Amber/Red 基础语义色；容器最大宽度 1420px；有 12px panel radius、基础 shadow、badge、tabs、table 和 card class。

可复用：Inter/PingFang/Microsoft YaHei 字体栈、最大宽度、基础语义色、panel/table/tabs 结构。

需要重构：

- token 只覆盖少量颜色，没有完整 Surface/Border/Spacing/Typography/Focus token；
- CSS 高度压缩在少数超长行中，维护和渐进迁移困难；
- 没有统一 8px spacing system 或 `font-variant-numeric: tabular-nums`；
- Active navigation 不根据当前路由设置；Seller Analysis 被做成高饱和渐变 CTA；
- 首页存在 score ring `/100`，与 V2 禁止无明确意义 Market Score 的方向冲突；
- V2 可改为深色，但应通过 tokens 和组件逐步迁移，不应一次性重写全部 CSS。

## 12. Existing Chart System

项目没有图表依赖。现有“图表”由 CSS/DOM 实现：

- 产品历史：绝对定位的圆点，没有连接线、键盘可访问 tooltip 或事件 marker；
- 数据质量时间轴：CSS 柱状块；
- coverage/progress：CSS progress bar；
- readiness score：conic-gradient 圆环。

优点是轻量。缺点是无法直接支撑多产品 Compare、Rank Line + Event Marker、统一 tooltip 和可访问交互。V2 仍可避免大型 chart framework，但需建立小型共享 SVG chart primitive；只有功能复杂度证明必要时再引入轻量库。

## 13. Existing Responsive Strategy

- Desktop-first；
- `max-width:1050px`：隐藏整个主导航、两栏变一栏、部分 grid 变两列；
- `max-width:650px`：页面 padding 缩小、filters/tabs/报告列表重排、表格/矩阵滚动。

主要问题：

- 小于 1050px 时主导航直接 `display:none`，没有替代菜单，违反“Navigation 可访问”；
- 没有针对 1366×768、1440×900、1920×1080 的截图 QA 证据；
- 首页内容密度较高，1366×768 不可能保证第一条完整 Signal，因为首页尚无 Signal-first 结构；
- 表格可滚动是可复用基础，但 sticky header、数字右对齐和长标题布局未统一；
- modal/tooltip 尚不存在，无法验证移动端约束。

## 14. V2 Requirement Mapping

| V2 能力 | 状态 | 审计判断 |
| --- | --- | --- |
| Market Context | Partially Exists | US 和三个 category 已配置；无统一组件、segment、URL 继承 |
| Product Classification | Partially Exists / Reusable | 仅配件榜有少量标题规则；缺 Machine/Electric/Gas/Cordless/Unknown 与 confidence |
| Brand Normalization | Partially Exists | 通用 schema 支持 brand/alias；当前 BS 数据无 verified brand，未接主链路 |
| Entry/Exit/Re-entry | Partially Exists | 日度 entry/exit 可复用；First Seen/Re-entry 缺失，部分 SQL 语义不安全 |
| Rank Trend Engine | Partially Exists | 1D、weekly net、movement bands 可复用；缺 3D/7D/30D、Rising/Strong/Falling 统一引擎 |
| Presence | Partially Exists | daysPresent/Top10Appearances 可复用；缺有效日分母、Top30/Top10 百分比和 consecutive |
| Rank Stability | Missing | 只有 Top10 stability 与最大位移，不是产品 Rank Stability |
| Review Momentum | Missing | 有历史 review count 和 coverage gate；无 growth/velocity/momentum |
| Market Turnover | Partially Exists | 有日度 entry/exit；无 7D aggregation、frequency 和 Low/Medium/High |
| Brand Concentration | Missing | 当前 concentration 非品牌指标 |
| Market Volatility | Partially Exists | 有 absolute movement、Top10 replacement、entry/exit 原料；无统一等级规则 |
| Signal Engine | Partially Exists / Reusable | 已有日度 Seller Signal 基础；缺 V2 类型、统一 schema、Watch、confidence、deep link |
| Overview | Already Exists / Needs Refactor | 页面成熟但层级与 V2 相反，应 Signal-first |
| Market | Missing / Reuse Insights | 可复用当前分析原料，需新信息架构 |
| Products | Partially Exists | 当前仅三个 leader；缺全产品表、filters、排序、Presence 等 |
| Product Detail | Partially Exists | 有事实和历史点；缺统一趋势、Presence、Review、Timeline |
| Product Compare | Missing | 无选择器、比较表、多序列图 |
| Brands | Missing | 无 verified brand 数据和页面 |
| Brand Detail | Missing | 同上 |
| Alerts | Partially Exists | `/analysis` 有 Seller Alert；缺专用入口、V2 严重度和 filter model |
| Daily Market Brief | Partially Exists / Reusable | 日报、在线日报、Seller Alert 已有；需合并为 V2 Brief presentation |
| Weekly Market Report | Already Exists / Needs Refactor | 周报链路成熟；需改为消费统一 Intelligence Layer |
| Data Status | Partially Exists | 质量信息丰富但散在首页/Insights；缺专页/组件 |
| UI Design System | Partially Exists | 有基础 tokens/classes；缺 V2 shared components 和系统化 tokens |
| Responsive QA | Partially Exists | 有两级 CSS；无目标分辨率截图 QA，移动导航缺失 |
| Accessibility | Partially Exists | 有 lang、nav label、部分 focus/aria；全局 focus、tab semantics、图表/移动导航不足 |

## 15. Actual Missing Capabilities

按依赖顺序，真正缺失的是：

1. 一份全系统唯一的 Valid Market Day selector；
2. Analytical Market 过滤模型以及 Product Type classifier；
3. 可验证 Brand 数据来源与 alias normalization；
4. 统一多周期 rank series API（1/3/7/30 个有效市场日）；
5. First Seen/New Entry/Re-entry/Exit 状态机；
6. Presence、consecutive、rank stability；
7. Review growth/velocity/momentum；
8. Brand seats/seat share/expansion/concentration；
9. Turnover/volatility；
10. V2 Signal schema、config、priority 和 evidence；
11. Market/Brand/Compare/Alerts/Data Status 页面；
12. V2 shared UI components、responsive screenshot QA 和基础 accessibility closure。

Crawler、回执、备份、邮件、报告 PDF 和网站同步不是 V2 的实际缺口。

## 16. Schema Changes Actually Required

### PostgreSQL

建议最小新增一个当前 Best Sellers 专用的产品维度，而不是强行复用未连接的通用 product 表：

- `(marketplace, asin)` 唯一键；
- `product_type`；
- `classification_confidence`；
- `classification_rule_version` / `classification_basis`；
- `raw_brand`（仅当有可验证来源时）；
- `normalized_brand_id` 或稳定 brand key；
- `first_seen_market_date` 可动态 `MIN(market_date)`，不要求首版持久化。

Brand alias 可以复用现有 `brand`/`brand_alias`，但必须先定义 Best Sellers ASIN 如何关联；若为了隔离当前链路新增专用 brand dimension，也必须避免与现有表形成第二份相互矛盾的 canonical truth。

不建议持久化 3D/7D/30D、Presence、Stability、Review Velocity、Turnover、Volatility、Signal Priority；先动态计算，性能不足再缓存/物化。

### D1

D1 必须新增同步后的 product metadata/brand mapping，或把经过验证的分类与品牌字段加入独立维度表。不要把这些字段复制到每一日 observation。Drizzle schema、SQL migration、`ensureSchema` 兼容路径和 sync contract 必须一起更新。

Market Context/Segment 第一版可放配置与 classifier，不一定需要表。Signals 第一版可动态返回，不一定需要 D1 持久表。

## 17. API Changes Actually Required

建议保留现有 API 并渐进扩展：

- 为所有业务 API 统一 `marketplace/category/segment/date/window` query contract；
- 扩展 `/api/public/overview` 返回 V2 summary、4 KPI、Top Signals、Brand Movement、Market Structure；
- 增加或统一 Market endpoint，返回 movers/entrants/brands/price/status tabs 所需结构；
- 扩展 Products list API，支持 search、type、trend、rank、price、presence、sort、pagination；
- 扩展 Product detail，返回有效日 series、Presence、Review、事件 timeline；
- 增加 Compare endpoint（2–5 ASIN，统一 context/window）；
- 增加 Brands list/detail endpoint；
- 增加 Alerts endpoint（High/Watch/type/context filters）；
- 增加 Data Status endpoint，公开完整日、字段覆盖、缺失/失败状态，不泄漏本地运营细节；
- 同步 bundle 增加 product metadata/brand/classification，并保持 receipt-bound、atomic、versioned。

现有 `/rankings` 应继续只返回 Raw Ranking；不要给它套 Analytical Market 过滤。

## 18. UI Changes Actually Required

- 导航收敛为：总览｜市场｜产品｜品牌｜榜单｜报告，右侧 Alerts/Data Status，Methodology 辅助入口；
- 建立统一可分享的 MarketContext；
- Overview 改为 Summary → 4 KPI → Top 5 Signals → Brand Movement → Market Structure；
- `/rankings` 保留 Raw Amazon Ranking；
- 新 Market 页面承载 Analytical Market 的 Movers/Entrants/Brands/Price/Status；
- Products 从三张 leader card 升级为真正表格；
- Product Detail 增加统一 rank components、Presence、Reviews、Timeline；
- 新 Compare、Brands、Brand Detail、Alerts、Data Status；
- 建立 V2 tokens 和共享组件，再逐页迁移；
- 移除首页 `/100` readiness score 的主视觉地位，但把底层质量信息迁入 Data Status；
- 增加 loading skeleton、No Data/Incomplete/Error 的明确区分；
- 修复移动导航、全局 focus、chart/tooltip keyboard access。

## 19. Migration Risks

1. 双数据库、双 schema：PostgreSQL 与 D1 必须同步演进，否则本地计算与网站展示会漂移；
2. 通用 product/brand 与 Best Sellers 专用历史没有外键连接，直接复用可能造成错误 join 或重复主数据；
3. D1 同时存在 Drizzle migration 和运行时 `ensureSchema`，新增字段必须确保老站点可幂等升级；
4. immutable report key/contract 已投入使用，修改 JSON schema 需版本升级，不应原地改变旧归档语义；
5. 旧快照缺 discounts，仓库 seed 又比本地真实历史更旧；backfill 必须允许未知，不可把 absence 解释为 false；
6. classifier/brand 规则版本升级会改变历史 Analytical Market，必须保留 rule version 或可重算边界；
7. 旧页面和测试依赖当前字段/文案，需渐进兼容，Phase 11 才处理 redirect/remove；
8. PostgreSQL view 依赖顺序已存在 `DROP/CREATE`，新增 valid-day view 应避免破坏下游 view。

## 20. Data Risks

- Brand 是最大数据风险：当前 Best Sellers 快照无 verified brand，不能从标题强行推断；
- 产品分类会有标题歧义，必须允许 `unknown` 和 low confidence；
- 2026-08-19 是真实失败日，V2 必须把 08-18 → 08-20 当相邻有效市场日，而不是自然日，也不能制造 08-19 Exit；
- 网站 product history 当前未过滤 incomplete category day；
- PostgreSQL exit view 未绑定 quality，不能直接作为 V2 exit truth；
- seed fallback 是 2026-08-12 固定历史；D1 故障时继续展示 derived KPI 会造成时效误解；
- Review Count 虽有历史，但 Amazon 展示/解析异常也可能产生不可单调数据；增长计算要处理 missing 和负差，不得自动归零；
- Price 是可见快照值，不能自动 forward-fill 后当真实当前价格；
- 同一 ASIN 可能同时出现在多个榜单，产品级指标必须始终绑定 Market Context；
- Product image 当前没有可信字段，ProductIdentity 首版应允许无图，不得用虚假商品图。

## 21. Test Gaps

现有测试健康度很高：

- PowerShell/Pester：271 passed，0 failed；
- Python collector：80 passed，0 failed；
- Web Node tests：首阶段 55 passed、构建后 79 passed，共 134 passed，0 failed；
- vinext production build：成功；
- ESLint：成功，无输出错误。

但 V2 PRD 指定的核心测试尚缺：

- Machine classifier：Electric/Gas/Cordless/Gun/Hose/Nozzle/Unknown；
- Brand alias/case normalization；
- First Seen/New Entry/Re-entry/Exit 的完整状态机；
- 1D/3D/7D/30D 有效日窗口；
- Rising/Strong Rising/Falling；
- Top30/Top10 Presence 和 consecutive；
- Rank Stability；
- Review 7D/30D growth、velocity、momentum 与 missing/negative cases；
- Brand seats/share/expansion/concentration；
- 7D turnover/new-entry frequency；
- Market Volatility Low/Medium/High；
- V2 High/Watch/No Alert；
- Failed/partial day 穿过每一项 V2 算法的参数化测试；
- 1366/1440/1920 screenshot regression 与横向 overflow；
- keyboard navigation、focus order、tooltip、mobile menu 的自动化/人工 QA。

## 22. Accessibility Issues

- 1050px 以下主导航完全隐藏且无替代入口，是最高优先级问题；
- 全局 button/input/select/link 没有统一 `:focus-visible`，只有 Seller Intelligence 相关控件有明确 focus；
- `RankingExplorer` 使用 `role=tab`，但没有完整 keyboard tab behavior、`aria-controls` 和 tabpanel 关联；
- `AnalysisCenter` 的模式按钮只是视觉 tabs，没有明确 ARIA 状态；
- 产品历史点依赖 `title` hover，键盘和触屏无法等价访问；
- 色彩多数有文字辅助，但 progress、score ring 和 status dot 仍有视觉依赖；
- 当前表格缺 caption/scope，数字列未统一对齐；
- Link 与 Button 的视觉边界并非全站一致；
- active primary navigation 没有 `aria-current`；
- loading 多处仍显示文字“正在…”，没有 skeleton/`aria-busy` 统一策略。

## 23. Performance Risks

- `loadVerifiedDashboardFromStore` 每次请求并行读取全部 snapshots、category_days 和 observations，再在 JS 内过滤；数据按日累积后会线性变慢；
- Seller live/Overview 在动态页面重复构造 history、map 和 signals，没有请求级/短期结果缓存；
- D1 `listObservations()` 是全表扫描式读取，虽然已有 ASIN/category-date 索引，但 overview 查询没有按窗口裁剪；
- V2 如果一次计算所有产品 30D Presence、Review、Brand 与 Signals，会放大当前全量读取成本；
- Product detail 的 ASIN/date query 已有索引，是较好的复用点；
- 报告生成和网站实时计算目前有两套实现，规则增长会增加 CPU 和一致性成本；
- CSS 无图表依赖且 bundle 很轻，这是应保留的优势。

建议：新增按 context + valid window 的 server-side queries；在 Intelligence Layer 上做 request memoization/短 TTL cache；用解释性 profiling 结果决定是否物化，不提前把所有指标写库。

## 24. Recommended Implementation Plan

### Phase 1 — Data Semantics

1. 定义唯一 `MarketContext` 类型和 URL contract；
2. 定义唯一 `ValidMarketDay` selector，并修正 PostgreSQL/web/local report 的语义差异；
3. 建立版本化 Product Classifier，先覆盖 Pressure Washers Machine/Accessory；
4. 明确 Brand 数据来源：优先 verified metadata/人工 alias，不允许标题猜测；
5. 新增最小 product metadata schema + D1 sync migration；
6. 用现有 2026-08-18、失败的 08-19、2026-08-20 构造跨缺失日回归测试。

### Phase 2 — Intelligence Engine

1. 先实现纯函数时间序列和事件状态机；
2. 再实现 Presence/Review/Brand/Market 指标；
3. 最后把现有 Seller Signals 映射到 V2 Signal schema；
4. 所有阈值放同一 config，PowerShell 报告和网站消费同一版本化结果；
5. 保留旧 Opportunity/Rank Influence，但不接 V2 UI。

### Phase 3–4 — Foundation and Overview

1. 建 token 和共享组件，不全站重写；
2. 先把 Overview 做成 V2 reference page；
3. D1 不可用时进入明确 Data Status/Error state，不再用陈旧 seed 生成“今天”信号；
4. 完成三个 desktop 尺寸和 keyboard QA 后再扩页面。

### Phase 5–10 — Vertical Slices

按 Market → Products/Detail → Compare → Brands → Alerts → Reports 顺序，每页只消费 Intelligence Layer；Raw Rankings 保持独立。

### Phase 11 — Cleanup

确认数据一致、功能覆盖和测试后，再处理 `/insights`、旧 `/analysis` 工作区、重复 CSS/组件、redirect 和 dead code。

## 25. Files Likely To Change

### 数据与配置

- `config/categories.json`
- 新增 `config/product-classification.*`
- 新增 `config/brand-aliases.*`（仅保存可审计 alias）
- 新增 `config/intelligence-thresholds.*`
- `db/migrations/` 新增迁移，不修改旧迁移
- `web/db/schema.ts`
- `web/drizzle/` 新增 migration/snapshot

### 本地分析与发布

- `src/SellerIntelligence.psm1`
- `src/BestSellersWeeklyAnalysis.psm1`
- 新增集中 Intelligence 模块，逐步替代重复计算
- `scripts/New-SellerIntelligenceReports.ps1`
- `scripts/New-OnlineAnalysisReports.ps1`
- `scripts/New-DashboardSyncBundle.ps1`
- `scripts/Publish-BestSellersDashboard.ps1`

### 网站数据层/API

- `web/lib/analytics.ts`（建议拆为兼容 facade + 新 intelligence 子模块）
- `web/lib/live-dashboard-data.ts`
- `web/lib/dashboard-store.ts`
- `web/lib/seller-intelligence.ts`
- `web/lib/sync-contract.ts`
- `web/lib/catalog.ts`
- `web/app/api/public/overview/route.ts`
- `web/app/api/public/rankings/route.ts`（仅增加统一 context/date 兼容，不改变 Raw 语义）
- `web/app/api/public/products/[asin]/route.ts`
- 新增 market/products/compare/brands/alerts/data-status API routes

### 网站 UI

- `web/app/components/SiteShell.tsx`
- `web/app/components/PageHeader.tsx`
- 新增 MarketContext、MetricCard、SignalCard、RankDisplay、RankDelta、ProductIdentity、Badge、DataStatus、EmptyState、Tooltip、Timeline 组件
- `web/app/page.tsx`
- `web/app/rankings/*`
- `web/app/products/*`
- 新增 market/compare/brands/alerts/data-status 页面
- `web/app/reports/*`
- `web/app/methodology/page.tsx`
- `web/app/globals.css`
- `web/app/enhancements.css`（迁移完成后合并/清理）

### Tests

- `tests/SellerIntelligence.Tests.ps1`
- 新增 V2 Intelligence Pester tests
- `web/tests/analytics.test.mjs`
- `web/tests/live-dashboard-data.test.mjs`
- `web/tests/rendered-html.test.mjs`
- 新增 classifier/brand/events/trends/presence/review/brand/market/signal/API/a11y tests
- 新增 screenshot QA 资产与检查流程

# Scope Reduction Suggestions

| 主要需求 | 建议 | 原因 |
| --- | --- | --- |
| Crawler | Reuse existing | 已有合规、完整、回执和失败保护；V2 无阻塞问题 |
| Raw Ranking | Reuse existing | `/rankings` 与原始快照语义正确，只需统一 Rank 组件 |
| Market Context | Simplify | V2 只做 US；三 category；Pressure Washers 先完整支持 segment，其它 category 先 All Bestseller |
| Product Classification | Keep / Simplify | 先 rule-based + unknown；不做 ML，不要求首版全部低频配件都高置信 |
| Brand Normalization | Keep | Brand 页面依赖它；但先解决 verified source，再做 alias，不从标题猜测 |
| First Seen/Entry/Re-entry/Exit | Keep | 是市场变化情报的基础，不可删减 |
| 1/3/7/30D Trend | Keep / Simplify | 只做明确净变化和有效比较日比例，不做复杂 score |
| Presence/Stability | Keep / Simplify | 只做 Top30/Top10/consecutive + 简单标准差分级 |
| Review Momentum | Keep / Simplify | 只比较 7D 与 30D velocity；不推断销量 |
| Brand Seats/Concentration | Keep | 是品牌情报的最小核心；名称始终用榜单席位，不叫 Market Share |
| Turnover/Volatility | Keep / Simplify | 规则只使用 rank movement、Top10 replacement、entry/exit；输出 Low/Medium/High |
| Signal Engine | Reuse existing / Refactor | 迁移现有 Seller Signal，不新建第三套；统一为 High/Watch 和 config |
| Overview | Keep / Refactor | 必须 Signal-first；删除 `/100` readiness 主视觉，把质量移到 Data Status |
| Market | Keep | 承载 Analytical Market；首版用 tabs，不需要复杂自定义 dashboard |
| Products | Keep | 首版做单一高信息密度表，避免 card gallery |
| Product Detail | Keep / Simplify | 一张 rank timeline + 核心指标；不做产品独立报告 |
| Compare | Keep / Simplify | 只支持 2–5 个产品、核心表和一张 rank chart；不做保存/分享列表 |
| Brands/Brand Detail | Keep / Simplify | 只做 seats、Top10、7D expansion、avg rank、presence 和产品列表 |
| Alerts | Reuse existing / Refactor | 独立入口，但普通 activity 留 Market；不做通知订阅系统 |
| Daily Brief | Reuse existing | 以 V2 Engine 重新组装，不再新增一套算法 |
| Weekly Report | Reuse existing | 保留 PDF/归档/邮件链路，只替换数据来源为统一 Engine |
| Data Status | Reuse existing / Simplify | 迁移已有 quality/readiness 信息；一个紧凑专页/面板足够 |
| Dark UI | Simplify | 通过 tokens 渐进迁移；不一次性重写 CSS，不引入大型 UI 框架 |
| Charts | Simplify | 先做共享轻量 SVG；不引入重量级 chart library，除非 Compare/Timeline 无法合理实现 |
| Responsive | Keep | 只保证 PRD 指定桌面尺寸和基本移动可用；不做完整 mobile-first |
| Accessibility | Keep | 先关闭导航、focus、ARIA、非颜色表达和 tooltip 等基础问题 |
| Legacy Opportunity Score | Remove from V2 UI | 与 V2 禁止复杂 Momentum/Market Score 的原则冲突；保留历史代码和数据，不删除 |
| Seed fallback as “current” | Remove from V2 business pages | 可保留为开发 fixture，但生产 D1 故障应显示 Data Status/Error，不生成陈旧“今日”信号 |
| User accounts/Watchlist/AI/Sales estimates | Delay to V2.1+ | 明确不在 V2.0 范围，避免扩大数据和权限边界 |

## Final Audit Decision

建议批准进入 Phase 1，但附带四个前置决定：

1. V2 的唯一时间基线是“上一有效市场日”，需要统一替换网站当前的“紧邻 snapshot 不完整则停止比较”语义；
2. Brand 在得到可验证来源前显示 Unknown，不允许标题推断；
3. Product Classification 与 Brand metadata 使用独立维度，不污染 Raw Ranking；
4. V2 Signal Engine 以现有 Seller Intelligence 为迁移起点，并废止页面各自计算信号的方向。

Phase 0 到此停止，等待人工确认后再进入 Phase 1。
