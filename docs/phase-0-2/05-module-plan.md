# Phase 0 — 模块规划

## 1. 模块边界

| 模块 | 核心职责 | 输入 | 输出 | 不负责 |
|---|---|---|---|---|
| 1. Data Collection | 根据来源配置采集、限流、重试、保存原始载荷 | Source Definition | Raw Artifact、Collection Run | 业务信号判断 |
| 2. Database | 事务、幂等、主数据、历史快照、查询仓储 | 规范记录 | 持久化实体和视图 | 页面解析 |
| 3. Product Tracking | 排名变化、新品、上升产品、趋势指标 | 有效历史快照 | Product Metrics、Signals | 品牌归一规则维护 |
| 4. Brand Intelligence | 品牌规范化、份额、增长、新品牌、生态关系 | 产品/品牌历史 | Brand Metrics、Ecosystem Edges | Opportunity 总分 |
| 5. Opportunity Score | 分项规范化、加权评分、等级与证据 | 产品/品牌指标和信号 | Versioned Scores | 直接修改基础事实 |
| 6. Listing Analysis | Title/Bullet/Image/Review 分析 | Listing/Review 快照 | 需求、痛点、改进建议 | 数据采集调度 |
| 7. Report Generation | 报告查询、模板渲染、质量披露、归档 | 指标、信号、分析结果 | Markdown 报告和导出表 | 重算上游指标 |

横切组件：Configuration、Data Contracts、Quality、Observability、Scheduling、Secrets。它们作为共享基础设施，不复制到七个业务模块。

## 2. 模块契约

- Collector 只输出版本化的原始 artifact 与解析候选记录。
- Normalizer 输出统一字段，不暴露页面特有结构给下游。
- Repository 接受规范实体和快照，负责幂等与事务。
- Tracking/Brand/Score 只读取质量通过的数据集。
- Report 只消费已物化或可重现的结果，不内嵌核心计算规则。

## 3. 可扩展机制

- Collector Adapter：按来源类型适配，不按品类复制整套采集器。
- Category Registry：配置品类树、外部节点、搜索词、配件类型和目标数量。
- Rule Registry：新品、品牌、上涨和低竞争规则版本化。
- Analyzer Interface：Listing/评论/生态分析可独立扩充。
- Report Sections：按品类元数据生成章节，新品类无需修改核心模板引擎。

## 4. 并发约束

系统硬上限为 6 个并发任务；初始计划使用 4 个采集任务并行，保留资源余量。数据库合并、分析和报告均是依赖关卡，不与尚未完成的上游并行。

## 5. 责任防重叠

品牌规范化只在 Brand Intelligence/共享规范层维护；排名变化只在 Product Tracking 计算；评分只在 Opportunity Score 组合；报告不重复计算这些规则。这能避免同一逻辑在多个模块产生不同结论。

