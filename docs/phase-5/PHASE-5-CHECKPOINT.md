# Phase 5 检查点：证据驱动的机会分析

## 1. 完成内容

- 建立 `opportunity-score-v1.0.0`，使用原项目权重：排名增长 30%、评论速度 20%、评分 15%、新进榜信号 15%、品牌增长 20%。
- 缺失维度不会被猜测或按零分处理；可观测得分只在已有维度间归一化，同时用缺失权重和历史覆盖天数降低置信度。
- 少于 2 个市场日时统一标记 `BASELINE_INSUFFICIENT`；置信度低于 50% 时标记 `LOW_CONFIDENCE`，不输出高、中、低机会结论。
- 增加 `FAST_RISING`、`HIGH_RANK_LOW_REVIEW`、`NEW_CHART_ENTRY`、`REENTERED_CHART`、`HIGH_VOLATILITY` 和 `REVIEW_SURGE` 可解释信号。
- 建立版本化分析 artifact、PostgreSQL 分析运行表、商品信号表、最新结果视图和幂等导入函数。
- 真实现有快照已生成 60 条分析结果并入库。因为只有 1 个有效市场日，全部正确标记为 `BASELINE_INSUFFICIENT`，没有伪造机会结论。

## 2. 文件变化

| 路径 | 作用 |
|---|---|
| `src/BestSellersOpportunityAnalysis.psm1` | 机会评分、置信度、缺失维度和解释信号 |
| `scripts/New-BestSellersOpportunityAnalysis.ps1` | 从周度/滚动历史分析生成机会 JSON |
| `db/migrations/008_opportunity_analysis.sql` | 版本化分析运行、商品信号、导入函数和最新视图 |
| `src/BestSellersOpportunityPostgres.psm1` | 机会分析 artifact 的事务导入 SQL 与执行器 |
| `scripts/postgres/Import-BestSellersOpportunityAnalysis.ps1` | PostgreSQL 导入入口 |
| `tests/AmazonIntelligence.Tests.ps1` | 评分、基线门禁、缺失值、信号及导入契约测试 |

## 3. 测试结果

- Pester：**61 passed / 0 failed**。
- PostgreSQL 18.4：51 张应用表、15 个报告视图、10 个迁移，健康检查通过。
- 真实基线导入：1 个分析运行、60 条商品信号；重复导入后仍为 1 个运行和 60 条信号，幂等通过。

## 4. 当前限制

- 现有真实数据只有 2026-08-04 一个市场日，且该快照只有 Pressure Washers 与 Sump Pumps 各 30 条；不能据此判断趋势或机会等级。
- Pressure Washer Parts & Accessories 独立榜单需要从下一次成功三榜 Top 50 采集开始积累历史。
- 当前 Amazon 页面没有可靠品牌、卖家、FBA、首次上架日期字段，因此品牌增长和严格意义上的“新品”判定保持缺失；新进榜仅表示进入监控 Top 50。
- 评分不是销量预测，也不使用未经验证的销量估算。

## 5. 下一步计划

1. 累积至少 2 个有效市场日后启用排名变化和评论速度；达到 7 天后再允许完整周置信度。
2. 下一次三榜 Top 50 成功采集后启用独立配件榜子类型分布；当前无该榜真实记录时保持 `NO_CATEGORY_DATA`。
3. 只有获得结构化或经过审核的品牌字段后才启用品牌集中度，禁止从标题首词猜测品牌。

## 6. 市场结构分析扩展

- 新增固定美元价格带：`<25`、`25–49.99`、`50–99.99`、`100–199.99`、`>=200`，输出商品数、份额、Top 10 数、平均排名、均价、平均评分及评论中位数。
- 新增配件标题关键词分类，覆盖七个既定配件类型；保留全部命中类型、主类型、规则和分类依据。
- 品牌集中度在没有已验证品牌字段时返回 `UNAVAILABLE_NO_VERIFIED_BRAND_FIELD`，不把标题首词当作品牌。
- 真实 2026-08-04 基线已入库：Pressure Washers 有价格记录 29/30，Sump Pumps 30/30；独立配件榜无数据，正确返回 `NO_CATEGORY_DATA`。
- 新增迁移 `009_market_structure_analysis.sql`、市场结构运行表、价格带指标表、配件分类表和两个最新结果视图；重复导入保持 1 个运行、15 条价格带记录。

## 7. 价格、星级和评论数与排名的关联

- 新增 `rank-influence-v1.0.0`，以 `rank_strength = 101 - rank` 为结果变量，计算价格、星级、`log10(评论数+1)` 的 Spearman 单调相关。
- 输出每项指标的样本量、缺失覆盖、相关系数、方向和强弱，并补充价格带、星级带、评论量级的平均排名与 Top 10 占比。
- 真实单日横截面结果：Pressure Washers 的价格/星级/评论数相关系数分别为 0.5989、0.4032、0.3391；Sump Pumps 分别为 0.0652、0.3318、0.5471。
- 上述结果只代表当日榜单内的统计关联，不代表价格、评分或评论数导致排名变化。可见性、促销、产品类型和未观测需求都可能混杂结果。
- 当前历史只有 1 天，所有价格变化、评论增长与排名变化的纵向分析均标记 `INSUFFICIENT_SAMPLE`。
- 新增迁移 `010_rank_influence_analysis.sql`、关联结果表、分组摘要表和两个最新结果视图；修正后结果以追加的新分析版本保存，没有覆盖旧版本。

## 8. 分析就绪门禁

- 根据负责人要求，第一次有限周度分析固定在北京时间 **2026-08-10（周一）09:00**。即使数据覆盖不足，也会生成并醒目标注“初始基线/覆盖不足”。
- 此后，Phase 5 的机会、价格带、配件、品牌字段状态和排名关联分析只在每周周报中运行；日报只记录采集状态和明显排名变化。
- 三个独立榜单各自累计至少 **8 个完整 Top 50 市场日**仍是“完整覆盖”门槛；未达到时周报不得把结果描述为完整趋势或因果结论。
- 门禁只计入完整 Top 50；缺少排名、缺榜、重复或不连续的快照不会计作有效市场日。
- 在 2026-08-10 之前，日报和周报只发送中文 PDF 格式的采集进度，包括完整有效日/8、观测日、缺失天数和完整性问题；2026-08-10 后周报开始有限分析。
- 当前真实状态：Pressure Washers 与 Sump Pumps 各有 1 个仅 Top 30 的观测日，配件独立榜无观测；三个榜单均为 0/8 完整有效日，因此状态为 `COLLECTING_BASELINE`。
- 门禁以 `src/BestSellersAnalysisReadiness.psm1` 与 `scripts/Test-Phase5AnalysisReadiness.ps1` 实现，并经 7 日、缺失一条、8 日全完整三种情形测试。

## 当前状态

**Phase 5 的首次有限分析已排定为 2026-08-10；完整覆盖前分析仅出现在周报，且明确披露覆盖不足。**
