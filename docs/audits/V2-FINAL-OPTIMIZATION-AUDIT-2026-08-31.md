# Amazon BS Market Radar V2.0 最终优化审计

日期：2026-08-31  
基线：`e7c271c`，Web 测试 108/108 通过，生产构建通过。

## 当前架构

- Next/Vinext 服务端页面，D1 为公开站读模型；页面统一经 `loadLiveDashboard` 读取数据。
- 原始榜单与分析市场已在 API 层分离：`rankings` 保留原始 Top30，`overview` 支持 `segment=machines`。
- 产品分类由 `config/v2-product-classification.json` 与 `BestSellersDataSemantics.psm1` 集中维护，产品元数据持久化分类证据。
- 已有共享 `MarketContext`、`ProductIdentity`、`RankDisplay`、`SignalCard`、`MetricCard`、`EmptyState` 与抽屉导航。

## PRD 差距矩阵

| 领域 | 状态 | 审计结论 |
|---|---|---|
| Raw Ranking / Analytical Market 双层语义 | 部分完成 | API 已分层；榜单页是 raw，但标签不够明确；首页、市场、产品、品牌仍直接使用 pressure_washers 原始行。 |
| Machines 筛选 | 仍缺失 | 页面层 KPI、信号、品牌和集中度没有统一过滤到整机。 |
| 分类规则与优先级 | 部分完成 | 配件优先于整机且配置集中；缺少 `foam cannon` 等强配件规则及 PRD 指定样例回归。 |
| 信号分层 | 部分完成 | high/watch/entry/activity 类型存在，但首页文案与市场页没有显式分组，普通 Activity 仍可能与 Alert 同权展示。 |
| 产品短名 | 部分完成 | 表格使用共享截断；SignalCard 和动态抽屉未使用共享产品身份，抽屉只显示 ASIN。 |
| 数字格式 | 部分完成 |评论数已紧凑；价格、优惠、日期仍有多处各自格式化。 |
| 品牌集中度 | 仍缺失 | 首页以截断后的品牌变化集合计算 Top3，分母含原始配件；品牌页未 Top5 + Others，也无 Seat Share 定义。 |
| Market 页面 | 仍缺失 | 只有状态头和事件流，缺 Overview/Movers/Entrants/Brands/Price 与时间窗语义。 |
| Products 页面 | 部分完成 | 浏览器、搜索、过滤已存在；输入行仍是原始类目而非 Machines 分析市场。 |
| Alerts | 部分完成 | Seller workspace 存在，但缺面向用户的 High/Watch/All 紧凑视图；证据展示偏重。 |
| Data Status | 部分完成 | 完整度与字段覆盖已有；缺分类覆盖率和 Unknown 计数。 |
| Methodology | 部分完成 | 双层市场语义已有；缺 Classification Coverage、Seat Share、Movers 与 Event Feed 的明确术语。 |
| 响应式与可访问性 | 基础完成 | 抽屉焦点管理、ARIA、表格滚动已有；改造后需重新做三档桌面与移动检查。 |

## 最高影响问题

1. **P0 — 上下文与数据集合不一致**：页面显示“整机”，实际 KPI/信号/品牌可能包含配件。
2. **P0 — 分类样例覆盖不足**：强配件词缺口会把配件保留为 unknown，削弱 Machines 分析覆盖。
3. **P1 — 市场页语义混用**：Movers 与 Event Feed 尚未拆开，无法支持 1D/3D/7D/30D 的独立浏览模型。
4. **P1 — 品牌集中度不可审计**：Top3 分子、分母、Unknown 处理与 Seat Share 没有统一函数。
5. **P1 — 产品身份不一致**：信号与活动抽屉仍可展示超长标题或仅 ASIN。

## 可复用与需重构

- 复用：现有主题 token、导航、卡片/表格样式、D1/API、`ProductIdentity`、`RankDisplay`、分析比较结果。
- 小幅重构：`ui-intelligence.ts` 增加统一分析市场投影、品牌结构、格式化与信号分组；页面只消费这些结果。
- 新增：Market tabs/视图组件、分类覆盖指标、统一 compact product name。
- 不改：爬虫、历史数据、数据库 schema、现有路由与计算门槛。

## 预计修改文件

- `config/v2-product-classification.json`
- `tests/BestSellersDataSemantics.Tests.ps1`
- `web/lib/market-context.ts`, `web/lib/ui-intelligence.ts`, `web/lib/live-dashboard-data.ts`
- `web/app/page.tsx`, `market/page.tsx`, `products/page.tsx`, `brands/page.tsx`, `rankings/page.tsx`, `insights/page.tsx`, `methodology/page.tsx`
- `web/app/components/ProductIdentity.tsx`, `SignalCard.tsx`, `ShellNavigation.tsx`
- `web/app/v2.css`
- 对应 Web/Pester 测试与截图审计文档。

## 阻塞判断

没有数据安全、不可逆迁移或重大架构冲突。可在保持原始榜单、数据口径和现有路由不变的前提下渐进实施。
