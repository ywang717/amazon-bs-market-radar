# Phase 4 检查点：历史数据库系统

## 1. 完成内容

- 新增第6号 PostgreSQL 迁移，将无需 Amazon 凭证的 CPSC 公共安全情报纳入历史数据库。
- 建立 `public_intelligence_run`，按来源和市场日审计每次公开数据采集。
- 建立 `public_safety_notice`，保存公告当前状态、首次发现日和最后观察日。
- 建立只追加的 `public_safety_notice_observation`，以内容哈希保存每日不同版本，不删除历史。
- 建立 `public_safety_current` 和 `public_safety_daily_change` 两个视图，分别支持当前状态和首次出现/内容变化查询。
- 建立事务性 `ingest_public_intelligence(jsonb)` 数据库函数与 PowerShell 导入器。
- 每日 `PUBLIC_DATA_ONLY` 流水线现在按顺序执行：CPSC API → 原始 artifact → PostgreSQL 历史导入 → 受限报告 → QQ 邮件。
- 数据库失败会标记 `IMPORT_FAILED_RETRYABLE`，但不删除 artifact，也不阻断报告和邮件。
- 计划任务仍为每天北京时间09:00；市场日期按美国太平洋时区计算。

## 2. 文件变化

| 路径 | 作用 |
|---|---|
| `db/migrations/006_public_intelligence_history.sql` | 公共情报运行、公告、观察历史、视图和摄取函数 |
| `src/PublicIntelligencePostgres.psm1` | artifact 到 PostgreSQL 的事务导入 |
| `src/PublicIntelligence.psm1` | 为规范记录生成 SHA-256 内容哈希 |
| `scripts/Invoke-CredentialFreeDailyPipeline.ps1` | 接入历史导入并保持邮件容错 |
| `scripts/Invoke-ScheduledDailyPipeline.ps1` | 两种运行模式均先保证 PostgreSQL 可用 |
| `scripts/postgres/Test-PublicIntelligenceHistory.ps1` | 真实重复导入与视图集成测试 |
| `scripts/postgres/Test-LocalPostgres.ps1` | 校验32张表、7个视图和6个迁移 |
| `tests/AmazonIntelligence.Tests.ps1` | 历史迁移、哈希和导入 SQL 自动化测试 |

## 3. 测试结果

- PowerShell/Pester：**36 passed / 0 failed**。
- PostgreSQL 18.4 健康检查：32张应用表、7个视图、3个活动 Amazon 来源定义、6个已应用迁移。
- 使用真实 CPSC artifact 连续导入两次：1个公开运行日、1条安全公告、1个历史版本，`NO_DUPLICATES`。
- `public_safety_current` 返回1条当前记录，与实体数量一致。
- Windows 计划任务在 2026-08-04 09:00 成功执行，返回码0并完成邮件发送；下次运行时间为 2026-08-05 09:00。

## 4. 存在问题

- 没有 Creators API 凭证，因此数据库中不能形成真实 Amazon 排名、价格、评论或卖家历史。
- CPSC 是产品安全数据源，不代表 Amazon 市场表现；不能用于计算新品、新品牌、排名趋势或 Opportunity Score。
- 历史变化需要至少两个市场日的不同内容版本；当前真实样本只有一个公告和一个内容版本。
- 本机 PostgreSQL 曾因 Windows 共享内存映射错误487停止接受新连接，经正常 fast stop/start 后恢复；原始数据未删除。
- 计划任务采用 Interactive 登录类型，只有当前 Windows 用户已登录时才运行，避免保存 Windows 登录密码。

## 5. 下一阶段计划

1. Phase 5 只基于有证据的公共安全历史开发规则分析，不生成 Amazon 市场机会分数。
2. 增加“新召回”“公告内容变化”“风险关键词”和品类安全事件趋势检测。
3. 报告中加入7/30/90天安全事件计数与变化，但数据不足时明确显示覆盖天数。
4. 保持 Amazon 专属分析模块停用，直到获得获准数据源。

## 当前状态

**Phase 4 最小历史数据库系统已完成。公开安全情报具备可追溯、幂等、只追加版本历史；Amazon 市场历史仍受数据授权边界限制。**
