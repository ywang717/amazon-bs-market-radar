# Phase 0 — 每日工作流设计

## 1. 每日主流程

```text
读取配置与历史基线
        ↓
并行采集（最多 4 个计划任务，系统上限 6）
        ↓
原始数据落地与批次审计
        ↓
解析、清洗、规范化、去重
        ↓
质量门禁 ──失败──> 隔离、告警、保留上一有效日
        ↓通过
事务性更新维度 + 追加历史快照
        ↓
Data Merge / 市场日封账
        ↓
变化检测与 7/30/90 日指标
        ↓
Opportunity Score
        ↓
AI 分析（仅在确定性数据完成后）
        ↓
日报生成、归档、运行摘要
```

## 2. 任务依赖

允许并行：

- Task A：Pressure Washer Collector
- Task B：Sump Pump Collector
- Task C：Pressure Washer Accessories Collector
- Task D：Movers & Shakers Collector

所有达到当日完整性要求的采集任务结束后才执行 Data Merge。AI Analysis 必须等待数据库更新、变化检测和 Opportunity Score 全部成功。单项失败时报告不得伪装成完整市场日，必须标明缺口。

## 3. 市场日与基线

- 调度和储存均保留 UTC 时间，业务比较使用 `America/Los_Angeles` 市场日期。
- 每个来源每天允许多个运行批次，但只能有一个被标记为分析使用的有效快照。
- 首次有效日建立 baseline；第二个有效日开始计算日变化。
- “Yesterday”解释为前一个完整且有效的市场日，不盲目使用自然日前一天。

## 4. 重试与恢复

- 网络/瞬时错误采用有上限的指数退避；不可无限重试。
- 原始载荷已落地但解析失败时，可从 artifact 重放，无需再次访问来源。
- 写库以批次为单位保证幂等；部分失败不会产生半个有效市场日。
- 修复解析器后使用新解析版本重放，并保留旧结果的失效审计。

## 5. 质量门禁

至少检查：目标数量覆盖、必需字段完整率、业务键重复率、排名范围、价格/评分/评论范围、品类映射成功率、与历史相比的异常骤降。完整率需大于 95%，重复率需小于 1%。严重异常阻断分析；一般警告随报告披露。

## 6. 日报结构

输出：`Amazon_US_Market_Report_YYYY-MM-DD.md`

1. Executive Summary：今日变化、新增产品、新增品牌、重点机会、数据质量。
2. Pressure Washer：New Products、New Brands、Rising Products。
3. Sump Pump：New Products、New Brands、Rising Products。
4. Pressure Washer Accessories：New Products、Emerging Brands、Fast Growing Accessories、Bundle Opportunities。
5. Market Trend Analysis：品牌、价格、产品和新品方向趋势。
6. Methodology Footer：数据窗口、覆盖率、运行批次和规则/模型版本。

## 7. 可观测指标

每次运行记录：开始/结束时间、成功状态、采集数量、接受/拒绝数量、完整率、重复率、映射失败率、数据新鲜度、各阶段耗时、重试次数和报告路径。

