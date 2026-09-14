# Amazon BS Market Radar V2.0 — Phase 0 Re-Audit Report

- 复核日期：2026-08-28（报告批次标签）
- 实际执行时间：2026-08-29 CST
- 对照基线：`Amazon BS Market Radar V2.0 Final PRD`
- 复核范围：当前代码、品牌证据 artifact/receipt、历史快照不可变性、PostgreSQL/D1 元数据验收记录、公开网站部署记录、自动化测试与 2026-08-27 线上榜单数据
- 执行边界：本报告只记录已核实结果；不把 unknown 解释为品牌，不暴露秘密、数据库凭据、Site 内部标识或代理细节

## Executive Decision

**结论：V2.0 尚未完成，但 Phase 1 的可信品牌数据与元数据回填已经完成并通过验收。**

本轮已补齐此前最关键的品牌数据缺口：从 Amazon 商品详情页明确标注的 Brand 字段取得证据，完成 131 个历史 ASIN 的 receipt-bound 回填，并同步 PostgreSQL 与 D1 产品元数据。品牌结果仍严格区分 VERIFIED 与 unknown，不把标题、URL、店铺或推荐卡片当作证据。

仍不能把项目整体标记为 V2 完成，原因是统一 V2 Intelligence Engine、Market Context UI、Signal-first Overview、Market/Compare/Brands/Alerts/Data Status 页面、完整时间窗指标、Design System 迁移、响应式/无障碍 QA 与视觉回归等仍未完成。

## Fresh Verification Evidence

| 验证项 | 本次结果 |
| --- | --- |
| 回填批次标签/路径 | `2026-08-28`；`var/brand-enrichment/2026-08-28/amazon-brand-enrichment.json` 与同目录 receipt |
| artifact generated_at | `2026-08-28T19:45:45.346729Z`（原始 JSON） |
| artifact/receipt | 均通过校验；artifact SHA-256 与 receipt hash 均为 `621ced00a25a23a674a542dd532b1ddbb4988936943f7898024d581cbdb4cba6` |
| 请求 ASIN / artifact products | 131 / 131；ASIN 唯一 |
| verification_status | VERIFIED 122；MISSING 5；IDENTITY_MISMATCH 4；CONFLICT 0；VERIFICATION_BLOCKED 0 |
| VERIFIED 证据来源 | 122/122 为 `PRODUCT_OVERVIEW_BRAND_FIELD` |
| unknown | 9（MISSING 5 + IDENTITY_MISMATCH 4） |
| distinct normalized brands | 76（按现有 `config/v2-brand-aliases.json` 规则核算） |
| PostgreSQL / D1 最终覆盖 | 均为 131 total、122 known、9 unknown；`verified_metadata=122`、`unknown=9` |
| PG/D1 逐 ASIN 语义比较 | 14 个元数据字段 mismatch=0；classification evidence 仅做 JSON whitespace normalization |
| 网站发布 | Site version 21 已部署至公开地址：[Amazon BS Market Radar](https://amazon-bs-market-radar.warrenwangyihao.chatgpt.site/) |
| D1 publish 验收 | 131-row payload success；identical replay success/idempotent；deliberate conflict HTTP 409；D1 仍为 131/122/9，代表性品牌未改变 |
| 历史不可变性 | 30 个托管历史文件（15 snapshots + 15 receipts）before/after SHA-256 变化数为 0 |
| 2026-08-27 线上榜单 | 3 个类别各 30 行，rank 1..30 distinct，`complete=true` |
| Windows PowerShell/Pester | 343 passed，0 failed |
| Python collector unittest | 98 passed，0 failed |
| Web prebuild tests | 91 passed，0 failed |
| Web production build | 成功 |
| Web postbuild tests | 99 passed，0 failed |
| ESLint | 成功 |

## 1. Current Architecture

### Local runtime

- Windows PowerShell orchestration + Python collector + PostgreSQL；
- 采集、回执、导入、报告、备份、健康检查、网站发布相互设门；
- 品牌回填使用独立 artifact/receipt，不写回历史 ranking snapshot；
- 日度主链路仍生成 3 个类目各 Top30、报告、备份和发布状态。

### Website

- vinext/React/TypeScript/Vite；
- D1 保存快照、观测、报告元数据和 product metadata；R2 保存 PDF；
- 公开读取 API 与 Bearer-secret 同步 API 分离；
- 版本 21 已部署品牌 metadata refresh 兼容实现；metadata-only endpoint 不混入榜单快照写入。

### Operational state

- 2026-08-27 线上榜单保持 3 类别完整 Top30；
- 公开站点已部署 version 21；
- 131-row 品牌元数据 payload 已成功发布，重放幂等，冲突请求拒绝且无部分写入；
- 生产规模修复记录：version 20 的 131-row publish 因旧 132 bind limit 约束返回 500 且未写 D1；version 21 改为 JSON bounded conflict lookup + one atomic bulk upsert 后通过全量验收。

## 2. Existing Capabilities

### Already exists and should be reused

- Amazon US 三个独立榜单精确 Top30 采集；
- 失败、部分、缺失快照不冒充有效市场日；
- Receipt + SHA-256 + source metadata 绑定；
- `null` 保真、价格/评分/评论字段覆盖率；
- 日度排名比较、Top10 Entry/Exit、Top30 Entry/Exit、Discount change；
- 日报、周报、PDF、网站报告归档；
- PostgreSQL/D1 双端版本化同步；
- Product Classification 配置、规则版本、置信度与 evidence；
- Raw Brand / Normalized Brand 字段、alias 规则与本次 receipt-bound trusted enrichment；
- 有效市场日选择器；
- Raw Ranking 与 Analytical Market API 分层；
- Seller Intelligence 的日度信号与周度事实框架。

### Exists but is not organized as V2

- First seen date 已写入 metadata，但未形成 V2 Entrants UI；
- Daily rank move 已有，但没有 1D/3D/7D/30D 统一时间窗；
- Top10 stability 已有相邻日事实，但没有 Market Volatility/Turnover 聚合；
- competitor pool 有 `daysPresent`，但不是统一 Top30/Top10 Presence；
- Seller signal card 是页面内部实现，不是共享 `SignalCard`；
- Data quality 信息很强，但仍占据首页核心，而不是右上 Data Status；
- 品牌数据基础已具备，但品牌列表/详情及品牌分析 UI 尚未实现。

## 3. Existing Schema and Data Coverage

### PostgreSQL

Migration 012 已增加 `best_sellers_product_metadata`、product type、classification evidence/version、raw/normalized brand、brand source/alias rule、first/last seen market date 与 valid category day。最终品牌元数据为 131 行，其中 122 行可信品牌、9 行 unknown。

### D1

`product_metadata` 维度表保留 131 行；metadata refresh endpoint 只更新产品元数据。最终 D1 与 PostgreSQL 的 14 个字段逐 ASIN 语义一致，均无 mismatch。

### Brand evidence

- 122 个 VERIFIED 均来自详情页商品概览中的明确 Brand 字段；
- 5 个 MISSING 与 4 个 IDENTITY_MISMATCH 保持 unknown；
- CONFLICT 与 VERIFICATION_BLOCKED 均为 0；
- 76 个 distinct normalized brands 为实测结果，不是预设覆盖承诺；
- 任何未核验值均未被写成品牌，也未从标题或店铺文本推断品牌。

## 4. Existing Analysis Logic

### Reusable

- `compareRankings` 的方向正确：旧 rank - 新 rank；
- exact Top30 validator；
- valid category-day selector；
- field coverage/evidence gates；
- Seller daily signals：rank move、Top10 entry/exit、Top30 entry/exit、discount change；
- weekly net movement、large swing、entry/exit 和 discount transition；
- price band、rank influence、market structure 等旧分析可保留为旁路资产。

### Not yet V2 compliant

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

## 5. Existing UI Architecture

当前页面仍为 `/`、`/rankings`、`/products`、`/products/[asin]`、`/insights`、`/analysis`、`/reports`、`/methodology`。当前一级导航仍是旧结构；PRD 要求的 Market、Products、Brands、Alerts、Data Status 信息架构尚未完全进入 UI。

因此，本轮完成的是可靠品牌数据与同步基础，不宣称品牌列表/详情页面、品牌智能指标或完整 V2 UI 已完成。

## 6. Existing Design Tokens

现有 CSS 仍有 nav、ink、muted、line、bg、blue、green、amber、red、panel 等旧变量和两档响应式规则。当前实际仍是浅色页面 + 深色顶部栏，不是 PRD 所述 Dark Theme；Level 0–3 surface tokens、统一 semantic status token、全局 focus-visible 与视觉回归仍缺失。

## 7. Reusable Components

正式共享组件仍主要是 `SiteShell`、`PageHeader`、`QualityBadge`。Seller signal、empty state、ranking delta、tabs/filter、report row、data quality/status 等仍有提取为共享组件的空间。

## 8. Duplicate Components

Rank、Entry/Exit、movement、badges、empty states、tabs、evidence/coverage 和信号展示仍存在多套表达；本次品牌 evidence contract 已统一采集与回填边界，但尚未统一 V2 UI 消费路径。

## 9. Existing Chart System

仍无通用 chart library、Compare Rank Chart、统一 Tooltip/Axis/Grid/Event marker 与完整键盘/触屏等价访问；产品历史图主要依赖 hover/title，尚无视觉回归测试。

## 10. V2 Requirement → Existing Capability Mapping

| V2 能力 | 状态 | 结论 |
| --- | --- | --- |
| Market Context data contract | Partially Exists | API 支持 US/category/segment；UI 无统一 selector，跨页不继承 |
| Raw Ranking | Already Exists / Reuse | `/rankings` 保留原始 Top30，语义正确 |
| Analytical Market | Partially Exists | overview API 可过滤；没有市场页面和主 UI 消费 |
| Product Classification | Partially Exists | 规则、存储、同步、测试完成；真实覆盖仍为 59/131，其它 72 unknown |
| Brand Normalization mechanism | Already Exists | schema/config/tests 与 receipt-bound normalization 已有 |
| Brand evidence/backfill | Completed for Phase 1 data gate | 131 条 artifact；122 VERIFIED、9 unknown；来源全部受限于明确 Brand 字段 |
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
| Brand concentration/expansion | Blocked by V2 engine/UI | 可信品牌数据已具备，但统一指标与页面尚未实现 |
| Market volatility | Missing | 无明确算法、方法说明、测试 |
| Signal system | Partially Exists / Refactor | Seller signals 可迁移；类型、优先级、阈值、Evidence 未统一 |
| Overview V2 | Missing | 线上仍显示旧 Data Readiness Dashboard |
| Market page | Missing | 无 route |
| Products list | Missing | 当前无 PRD 要求的统一表格、筛选与分页 |
| Product detail | Partially Exists | 当前/最佳/在榜天数/历史点；缺完整 ranking/presence/review/timeline |
| Product Compare | Missing | 无 route/API/UI |
| Brand list/detail | Missing | 可信品牌数据已入库，但 route/API/UI 未实现 |
| Alerts | Partially Exists | 卖家分析有预警工作区；无右上入口、High/Watch 面板与 activity 分层 |
| Data Status | Missing | 质量信息存在但没有右上入口/独立面板 |
| Daily Brief | Partially Exists / Reuse | 有日报与 seller alert；未消费统一 V2 Engine |
| Weekly Report | Partially Exists / Reuse | 有周报链路；内容和算法未完成 V2 统一 |
| Design System Foundation | Missing | 只有少量共享组件和旧 tokens |
| Responsive baseline | Partially Exists | 有两档 CSS；1050px 以下导航直接隐藏且无替代 |
| Accessibility baseline | Partially Exists | jsx-a11y lint 可用；缺全局 focus、完整 tabs、chart/touch tooltip |
| Screenshot QA | Missing | 无 1366/1440/1920 证据 |
| Visual Regression | Missing | 测试栈无对应资产 |

## 11. Actual Missing Capabilities

按依赖顺序，当前仍阻塞整体 V2 的缺口是：

1. 统一 Intelligence Engine 与阈值配置；
2. Entry/Re-entry 状态机和有效日窗口；
3. 3D/7D/30D Trend、Presence、Stability、Review、Turnover、Volatility、Brand 指标；
4. V2 Signal schema：High/Watch/Market Activity + Evidence；
5. MarketContext UI/URL 继承；
6. Signal-first Overview；
7. Market、Products、Compare、Brands、Alerts、Data Status 产品面；
8. V2 Daily/Weekly report composition；
9. Design System、responsive、accessibility、screenshot QA。

可信 Brand 来源、历史回填、PG/D1 元数据刷新已不再是当前缺口，但品牌 UI 与品牌分析指标仍属于后续工作。

## 12. Schema Changes Actually Required

Phase 1 最小 product metadata schema 与 receipt-bound enrichment 已满足本轮品牌数据门槛，不建议再次新增重复产品维度。

后续仍需决定：是否需要独立 brand dimension/key、Signal 是否动态生成、event timeline 是否动态推导，以及 classifier/alias 规则升级如何保留 rule version 并可审计重算。

## 13. API Changes Actually Required

仍缺少或需扩展 market summary/movers/entrants/brands/price、products list search/filter/sort/pagination、product detail 多窗口/presence/review/timeline、compare 2–5 ASIN、brands list/detail、alerts、data status、V2 overview summary + Top5 Signals，以及所有核心 API 的统一 context/date/window contract。

现有 `/api/public/rankings` 应继续保持 Raw，不应改成 Analytical。

## 14. UI Changes Actually Required

- 导航收敛为 PRD 六项并增加右上 Alerts/Data Status；
- 建 MarketContext breadcrumb + selector；
- 首页移除 readiness score 的主视觉地位，改为 Top Signals；
- 增加 Market 五个 tabs；
- Products 改为统一高密度表格；
- Product Detail 增加完整指标、时间窗和事件 Timeline；
- 新增 Compare、Brands、Brand Detail、Alerts、Data Status；
- 报告中心只突出 Daily Brief 与 Weekly Report；
- 建共享 Rank/Product/Badge/Signal/Tooltip/EmptyState 组件后再迁移页面。

## 15. Migration Risks

1. **品牌数据风险已从“覆盖为 0”降为“持续 freshness 与冲突治理”**：当前 122 条是受证据约束的 observed result，9 条仍必须保持 unknown；
2. **双计算路径漂移**：PowerShell、web analytics、Seller reports 仍可得出不同口径；
3. **双数据库演进**：PostgreSQL 与 D1 contract 必须同步升级；
4. **历史 classifier 重算**：规则版本更新会改变 Analytical Market；
5. **旧报告不可变键**：V2 报告 schema 应版本化，不能原地改变已归档语义；
6. **seed fallback**：普通 dashboard 仍可回退旧 seed；V2 今日信号不得使用陈旧 seed 冒充实时；
7. **全表读取性能**：overview/product loader 仍读取大量全量记录，历史增长后会线性变慢；
8. **工作区卫生**：旧 worktree 与临时内容仍需人工确认，不能自动删除；
9. **健康检查漂移**：`Test-LocalPostgres.ps1` 仍断言 15 个视图，而当前 schema 已有 16 个。

## 16. Test Gaps

本轮已通过品牌 evidence、artifact/receipt、metadata refresh、PG/D1 语义一致性、历史不可变性、公开发布幂等与冲突保护验收。PRD 核心仍未覆盖：

- First Seen/New Entry/Re-entry/Exit 完整状态机；
- 1D/3D/7D/30D 有效日窗口；
- Rising/Strong Rising/Falling；
- Top30/Top10 Presence、consecutive days、Rank Stability；
- Review 7D/30D growth/velocity/momentum；
- Brand seats/share/expansion/concentration 的统一 Engine 实现；
- 7D turnover、新入频率、volatility；
- High/Watch/Market Activity；
- Price × Rank 同期事件与非因果文案；
- Compare 2–5 产品与统一时间轴；
- 1366×768、1440×900、1920×1080 screenshot QA；
- mobile navigation、keyboard tabs、tooltip、focus order；
- visual regression。

## 17. Accessibility Issues

- 1050px 以下主导航直接 `display:none`，没有 menu 替代；
- 主导航没有 active route/`aria-current`；
- Ranking tabs 缺完整关联与 arrow-key 行为；
- 产品 rank chart 点依赖 hover/title，键盘与触屏不可等价访问；
- 全局 focus-visible 未建立；
- table 缺 caption/scope 统一策略；
- loading 缺统一 skeleton/aria-busy；
- progress/score ring/status dot 仍有视觉依赖。

## 18. Highest Impact UI Improvements

1. 首页改为 Top5 Signals，Data Quality 移到右上 Data Status；
2. 建 MarketContext 并贯穿总览/市场/产品/品牌/报告；
3. 建统一 RankDisplay/RankDelta/ProductIdentity/SignalCard；
4. 建 Products 表格和 Product Detail Timeline；
5. 增加 Market 与 Brands 页面，让 Analytical Market 和可信品牌数据进入产品面；
6. 修复移动导航和全局 focus-visible；
7. 明确选择 Dark V2 迁移，并补齐 screenshot/visual regression QA。

## 19. Recommended Implementation Plan

### Gate 0 — Phase 1 业务可用性

1. ✅ 确认 verified Brand 来源；
2. ✅ 回填 131 个历史 ASIN 并输出 artifact/receipt 与覆盖率；
3. ⏳ 将 MarketContext 写入 URL/UI，保证跨页继承；
4. ⏳ 明确 Sump Pumps 首版是否只支持 `all_bestsellers + unknown product_type`。

### Phase 2 — Unified Intelligence Engine

按 PRD 顺序实现纯函数与参数化测试：event state machine → windows/trend → presence/stability/review → market/brand → signal。统一阈值配置，旧 Seller Intelligence 作为 adapter。

### Phase 3–4 — Design Foundation + Overview/Market

先完成 tokens 和共享组件，再把 Overview 做成视觉样板；通过 1366/1440/1920 与 keyboard QA 后再实现 Market。

### Phase 5–9 — Vertical slices

Products → Product Detail/Timeline → Compare → Brands → Alerts → Reports。每个页面只消费统一 Engine/API。

### Phase 10 — Cleanup & QA

最后处理旧 routes、重复 CSS、seed fallback、performance cache、responsive、accessibility、visual regression 和旧 worktree 清理。

## 20. Final Re-Audit Decision

**不建议把当前状态标记为“V2 完成”。**

可以确认：Phase 1 的品牌数据业务可用性已完成——可信来源、ASIN 身份核验、artifact/receipt、PG/D1 元数据同步、幂等/冲突保护和历史不可变性均有验收证据。下一阶段应进入统一 Intelligence Engine 与 MarketContext/UI，而不是把当前 76 个品牌直接扩展成未经定义的品牌分析页面。

本报告保留 unknown 结果和未完成项目，不把数据回填的完成误报为产品 V2 全量完成。
