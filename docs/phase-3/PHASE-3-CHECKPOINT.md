# Phase 3 开发检查点：数据模型与最小采集链路

## 1. 完成内容

- 记录 PostgreSQL + 零依赖 PowerShell 参考实现的技术决策。
- 建立 PostgreSQL 初始迁移：市场、品类、来源、品牌、卖家、产品、运行审计、原始载荷、质量问题、排名/Offer/Listing/Review 历史、指标、信号和 Opportunity Score。
- 建立 Daily Ranking、New Product Entry、New Brand Tracker、Rising Products、Trend Analysis 五个报表视图。
- 建立三大根品类与七类重点配件的配置和种子数据。
- 实现 `canonical-observation-v1` 统一观测契约。
- 实现 fixture 采集适配器、字段规范化、拒绝原因、SHA-256 确定性记录键和幂等 JSONL staging。
- 提供命令行入口和自动化测试入口。
- 实现 raw artifact 内容寻址归档、采集运行 manifest、重复检测与质量门禁。
- 质量通过的批次发布到数据库 outbox；失败批次进入隔离且仍保留原始数据和审计证据。
- 新增 PostgreSQL 事务摄取 API：开始批次、摄取统一观测、结束批次。
- 核对 Amazon 官方最新接口并确定 PA-API 5 不再作为新开发目标。
- 实现 Creators API `SearchItems` 适配器：OAuth 2.0、Top 50 请求规划、US marketplace、响应规范化和传输层注入测试。
- 实现可执行的五页 Top 50 运行器：一次 token、逐页响应归档、跨页去重、统一质量门禁和单批 outbox 发布。
- 将 fixture 与官方 API 共用的发布逻辑抽取为 `Publish-CollectionResult`，避免两套质量/审计规则漂移。
- 建立本地三品类 Search 来源配置，全部通过审核状态、UUID、索引、速率和重试参数校验。
- 实现429/5xx/网络错误的有界指数退避和跨页1 TPS保守限速。
- 建立 PostgreSQL 三来源种子迁移、outbox SQL生成器和 `psql` 事务导入入口。
- 实现三品类每日 Search 编排、逐来源失败隔离、最多6来源门禁和每日汇总 manifest。
- 每日错误摘要会移除已知凭证值和 Bearer token，避免外部错误信息造成密钥落盘。
- 配置工作区隔离的 PostgreSQL 18.4 开发实例，仅监听 `127.0.0.1:55432`，不注册系统服务或修改 PATH。
- 在真实 PostgreSQL 中执行并追踪全部5个迁移，验证27张应用表、5个报表视图和3个活动来源。
- 使用真实事务摄取API连续导入同一3记录outbox两次，确认批次和三类事实表均无重复。
- 明确 Creators API 仅承担 Search Results；Best Sellers 和 Movers & Shakers 不使用搜索结果冒充。

## 2. 文件变化

| 路径 | 作用 |
|---|---|
| `.gitignore` | 排除运行数据、密钥和编辑器文件 |
| `docs/adr/0001-runtime-and-database.md` | 技术决策、约束与后果 |
| `config/categories.json` | Category Independent 品类注册表 |
| `db/migrations/001_initial_schema.sql` | PostgreSQL 核心数据模型 |
| `db/migrations/002_reporting_views.sql` | 五类业务输出视图 |
| `db/migrations/003_seed_reference_data.sql` | 市场、品类和草案评分模型 |
| `db/migrations/004_ingestion_api.sql` | PostgreSQL 事务性摄取函数 |
| `src/AmazonIntelligence.psm1` | 契约、校验、fixture collector、幂等 staging |
| `src/CreatorsApiAdapter.psm1` | 官方 Creators API SearchItems 适配器 |
| `config/sources.example.json` | 默认禁用的三品类官方搜索源示例 |
| `docs/phase-3/DATA-SOURCE-DECISION.md` | 官方资料、字段边界与来源决策 |
| `scripts/Invoke-FixtureCollection.ps1` | 可执行的最小采集纵向入口 |
| `scripts/Invoke-CollectionPipeline.ps1` | artifact、质量门禁、staging、outbox 流水线 |
| `scripts/Invoke-CreatorsApiSearch.ps1` | 审核启用后的官方 Search Top 50 入口 |
| `src/PostgresOutbox.psm1` | outbox 到事务 SQL 的生成和导入边界 |
| `scripts/Import-PostgresOutbox.ps1` | `psql` 导入入口 |
| `db/migrations/005_seed_search_sources.sql` | 三个已批准 Search 来源种子 |
| `docs/phase-3/RUNBOOK.md` | 凭证、运行、迁移、导入和核验手册 |
| `src/DailyCollection.psm1` | 三品类每日采集编排、隔离与脱敏摘要 |
| `scripts/Invoke-DailySearchCollection.ps1` | 每日 Search 执行入口 |
| `scripts/postgres/` | 本机PostgreSQL生命周期、迁移与集成测试 |
| `docs/phase-3/LOCAL-POSTGRES.md` | 本机SQL环境状态和运维说明 |
| `scripts/Test.ps1` | 自动化测试入口 |
| `tests/` | 合成测试数据与 Pester 测试 |

## 3. 测试结果

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

结果：**35 passed / 0 failed**。

覆盖：

- 3 个根品类和 7 个配件子类配置；
- 有效记录规范化与 100% fixture 完整率；
- 无效 ASIN、超范围排名、异常 Rating、负 Review Count 拒绝；
- 同一批次重复暂存的幂等性；
- 批次内部重复记录检测和重复率计算；
- 合格批次发布到 staging/outbox；不合格批次隔离且保留 artifact/manifest；
- 核心数据库实体、唯一记录键和五个报表视图存在性。
- PostgreSQL 批次开始、规范观测摄取和批次结束 API 存在性。
- Creators API Top 50 五页请求规划、OAuth token 合同和认证 header；
- 官方风格 SearchItems/OffersV2 响应到统一观测契约的字段映射。
- 完整五页、50 个唯一 ASIN 的离线端到端运行；
- 五个原始响应 artifact、50 行 staging 和单个数据库 outbox 发布；
- manifest/outbox 不含 access token 或 client secret。
- 三个本地来源配置验证、429退避序列和1 TPS参数；
- 50条规范观测的 PostgreSQL 事务 SQL 生成与三来源种子迁移。
- 三来源全部成功、单来源失败后继续、超过6来源提前拒绝；
- 每日 manifest 的敏感值与 Bearer token 脱敏。
- PostgreSQL 18.4真实迁移、重复迁移跳过、schema/view/source数量校验；
- outbox重复导入后仍保持1个运行批次、各3条Ranking/Offer/Listing和3行日报视图。

Smoke test：有效 Pressure Washer fixture 以 `SUCCEEDED` 完成，3 条记录发布；无效 fixture 以 `QUARANTINED` 完成，不产生 outbox，但保留原始 artifact 和运行 manifest。此前重复运行测试仍保持首次写入 3 条、第二次写入 0 条。

## 4. 存在问题

### 2026-08-04 补充：真实 Best Sellers 采集验收

- 三个独立 Best Sellers 节点及“仅在第一页滚动至排名 50、第二页从 51 开始”的规则已固定在 `config/best-sellers-sources.json`。
- 已新增 `BEST-SELLERS-BROWSER-COLLECTION-PROTOCOL.md`，把独立节点、字段边界、验证码/登录停止条件、质量门槛和不完整快照处理固化为可执行协议。
- 当日公开页面检查确认 Pressure Washers 页面可访问且首屏显示 1–30；当前浏览器会话在继续动态滚动时超时。因此没有把 30 条页面或第二页入口错误地当成完整 Top 50。
- 真实快照仍为 Pressure Washers 30、Sump Pumps 30、Accessories 0；三类均未通过完整性校验。Phase 3 的真实、无人值守 Top 50 采集器仍处于未验收状态。

- 本机PostgreSQL 18.4已配置并通过真实集成测试；生产数据库部署、备份和最小权限角色仍未设计。
- 当前机器没有 Python、Node 或 .NET SDK；采集参考实现采用 PowerShell 5.1。
- Creators API环境变量仍未配置；真实入口已经验证会在网络调用之前安全退出。
- 尚未提供可用的 Creators API 账户凭证、Browse Node 和访问频率，因此适配器没有启用，也没有发起真实请求。
- Creators API 适配器代码已经实现，但示例来源保持 `active=false`，没有账户凭证时不会发起请求。
- JSONL staging 是数据库写入前的追加落地区，不替代生产数据库。
- Opportunity 等级阈值仍未校准，种子模型明确标记为 `DRAFT`。
- Creators API 不提供 Best Sellers/Movers & Shakers 专榜操作，也无法可靠提供 FBA、Rating、Review Count、Coupon 和 First Available Date 的全部目标字段；这些字段保持 UNKNOWN/NULL，不做推断。

## 5. 下一阶段计划

1. 获得 PostgreSQL 运行环境后执行迁移集成测试并实现事务性 Database Writer。
2. 确认数据渠道、Amazon 节点和 Search 关键词后，实现第一个获准来源适配器。
3. 用 Pressure Washer 单来源完成 raw artifact → normalize → quality gate → database 的最小纵向链路。
4. 验收后扩展 Sump Pump、Accessories 与 Movers & Shakers，最多 4 个采集任务并行。
5. 数据连续运行形成基线后再进入变化检测与历史指标，不提前开发 AI 分析。

## 当前状态

**Phase 3 的本机最小纵向链路已完成：每日三来源编排、质量门禁、可重试 outbox、PostgreSQL 事务导入及摘要均已实现并验证。真实 Amazon 数据运行仅等待 Creators API 凭证。**

### 本检查点新增

- `src/DailyDatabasePipeline.psm1` 将每日采集结果逐来源写入 PostgreSQL。
- `scripts/Invoke-DailyPipeline.ps1` 提供采集到数据库的一体化命令。
- 采集失败会跳过对应数据库导入；单来源数据库失败会保留 outbox 并继续其他来源。
- 每日数据库摘要会记录采集和导入状态，同时脱敏数据库密码与 Bearer token。
- 新增 3 项数据库编排测试，覆盖全成功、采集部分失败和数据库部分失败。
- 新增 PostgreSQL 每日报告生成器，输出 Markdown 与 HTML，并显式披露数据质量和来源边界。
- 每日报告默认投递到 `746254487@qq.com`；QQ SMTP 授权码仅从进程环境读取。
- 邮件缺少凭证时安全跳过，发送失败时标记为可重试，且投递摘要不包含授权码。
- 新增无 Creators API 凭证的 `PUBLIC_DATA_ONLY` 模式，采集美国 CPSC 官方公开召回 API 的近90天有效资料。
- 降级报告明确排除 Amazon 排名、价格、评论、销量、新品/新品牌判定和 Opportunity Score，不对缺失数据进行推断。
- Windows 每日计划任务会自动检测凭证：完整时运行 Creators API 流水线，不完整时运行公开数据降级报告。
- 当前自动化测试总计 35 项，全部通过。
