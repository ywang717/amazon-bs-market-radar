# Phase 3 运行手册

## 1. 当前安全状态

- `config/sources.json` 已建立，三个 Search Top 50 来源为 `APPROVED_SEARCH_ONLY` 和 `active=true`。
- 配置不含凭证，并已加入 `.gitignore`。
- Creators API 凭证不存在时，入口在任何网络请求之前终止。
- Best Sellers 与 Movers & Shakers 尚无获准提供方，因此未配置。

## 2. Creators API 凭证

通过受控运行环境或当前进程的环境变量注入：

- `AMAZON_CREATORS_CLIENT_ID`
- `AMAZON_CREATORS_CLIENT_SECRET`
- `AMAZON_CREATORS_PARTNER_TAG`

不要把值写入 `.env`、JSON、PowerShell 脚本、命令历史、日志或项目文档。

使用本机交互式配置脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-CreatorsApiEnvironment.ps1
```

脚本依次提示输入 Client ID、Client Secret 和 Partner Tag。Client Secret 使用隐藏输入；示例尖括号不属于凭证内容。默认同时写入当前进程和当前 Windows 用户环境，以便每日计划任务读取。

## 3. 执行 Search Top 50

Pressure Washer：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-CreatorsApiSearch.ps1 `
  -SourceId '71cc7af1-35b1-4d19-8306-ff971db318ee' `
  -MarketDate 'YYYY-MM-DD'
```

Sump Pump：`34246971-247c-47ed-99a6-0f75d9e4ffb6`

Pressure Washer Accessories：`021052f6-47df-48a3-a066-da1469e773dc`

每个来源默认 1 TPS、最多3次请求尝试。429、5xx和无状态网络错误使用有界指数退避；其他4xx立即失败。

## 4. PostgreSQL 初始化

本机开发环境已配置完成，详见 [LOCAL-POSTGRES.md](LOCAL-POSTGRES.md)。

迁移必须按编号顺序执行：

1. `001_initial_schema.sql`
2. `002_reporting_views.sql`
3. `003_seed_reference_data.sql`
4. `004_ingestion_api.sql`
5. `005_seed_search_sources.sql`

生产连接信息使用 libpq 支持的受控环境配置。不要把密码放进连接 URI、脚本参数或仓库。

## 5. 每日三品类编排

凭证配置后，按同一市场日顺序执行三个 Search 来源：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-DailySearchCollection.ps1 `
  -MarketDate 'YYYY-MM-DD'
```

每日 summary 保存为 `var/daily/YYYY-MM-DD/daily-summary.json`。状态含义：

- `SUCCEEDED`：三个来源全部成功；
- `PARTIAL`：至少一个成功、至少一个失败；
- `FAILED`：没有来源成功。

初始模式为 `SEQUENTIAL_SHARED_RATE_LIMIT`。这是为了遵守账户共享 TPS，不与“最多6个任务”的上限冲突。单来源失败会被记录并脱敏，不阻止剩余来源执行。

## 6. PostgreSQL outbox 导入

当 PostgreSQL 与 `psql` 可用后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Import-PostgresOutbox.ps1 `
  -OutboxPath '.\var\outbox\<run-id>.json'
```

导入器生成单一事务：开始采集批次、登记所有 raw artifacts、逐条调用规范摄取函数、结束批次、提交。`psql` 使用 `ON_ERROR_STOP=1`，任一记录失败都会使执行失败，避免静默产生部分成功。

## 7. 验证

### 每日采集并自动写入 PostgreSQL

本机 PostgreSQL 启动且 Creators API 凭证已注入后，使用统一入口完成三来源采集、质量门禁和数据库导入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-DailyPipeline.ps1 `
  -MarketDate 'YYYY-MM-DD'
```

数据库编排摘要保存到 `var/daily/YYYY-MM-DD/daily-database-summary.json`。只有采集成功并通过质量门禁的 outbox 才会导入；采集失败的来源会跳过。数据库导入失败时，outbox 会保留以便重试，且不会阻断其他来源。

### 每日报告与 QQ 邮件

完整流水线在数据库导入后生成：

- `var/reports/YYYY-MM-DD/amazon-us-home-equipment-daily-report.md`
- `var/reports/YYYY-MM-DD/amazon-us-home-equipment-daily-report.html`
- `var/reports/YYYY-MM-DD/email-delivery-summary.json`

默认收件人为 `746254487@qq.com`。需要先在 QQ 邮箱设置中启用 SMTP 服务并生成授权码，然后仅在当前受控进程中注入：

```powershell
$env:DAILY_REPORT_SMTP_USERNAME = '746254487@qq.com'
$env:DAILY_REPORT_SMTP_AUTH_CODE = '<QQ SMTP 授权码>'
```

默认服务器为 `smtp.qq.com`、端口 `587`、启用 TLS。授权码缺失时仍会生成和归档报告，但邮件状态为 `SKIPPED_CREDENTIALS_MISSING`，不会尝试网络连接。授权码不得写入脚本、JSON、日志或命令历史；建议由任务计划程序的受控账户环境或凭证管理器注入。

可使用隐藏输入脚本为当前 Windows 用户配置环境变量（必须使用新生成且未在聊天或日志中暴露的授权码）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-EmailEnvironment.ps1
```

提示符不会回显授权码。不要输入示例中的尖括号。配置到用户环境后，需要启动新的 PowerShell 进程才能自动继承；脚本自身也会配置当前脚本进程。

只重建已有数据库日期的报告时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-DailyReport.ps1 `
  -MarketDate 'YYYY-MM-DD'
```

调试时可添加 `-SkipEmail`。邮件发送失败会记录为 `SEND_FAILED_RETRYABLE`，不回滚采集或数据库结果。

### Windows 每日计划任务

在系统时区为 `China Standard Time` 的机器上，注册每天北京时间 09:00 执行的任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Register-DailyScheduledTask.ps1
```

任务名为 `AmazonIntelligence-Daily-0900`，同一实例尚未结束时不会启动重叠实例。运行器会启动本机 PostgreSQL，以 `Pacific Standard Time` 计算 Amazon 美国市场日期，再执行采集、入库、报告和邮件。日志写入 `var/scheduler/`。

安全默认是仅在当前 Windows 用户已登录时运行，因此不会保存 Windows 登录密码。电脑在 09:00 错过执行时，任务会在恢复可用后补跑。Creators API 和 SMTP 凭证均可从当前用户环境读取。

Creators API 三项凭证不完整时，计划任务自动进入 `PUBLIC_DATA_ONLY` 模式，不尝试 Amazon 认证。该模式只调用美国 CPSC 官方公开召回 API，保存近90天与 Pressure Washer、Sump Pump 和重点配件相关的产品安全资料，并生成 `Amazon_US_Market_Report_YYYY-MM-DD.md/html`。

降级报告不会提供或推断 Amazon 排名、价格、评分、评论、卖家、销量、Best Sellers、Movers & Shakers 或 Search Top 50，也不会计算新品、新品牌、排名趋势和 Opportunity Score。报告标题与正文会明确标记 `PUBLIC DATA ONLY`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

真实运行后检查：

- manifest 状态为 `SUCCEEDED`；
- `CompletenessPercent > 95`；
- `DuplicatePercent < 1`；
- raw artifact 数量等于实际请求页数；
- outbox 不包含 token 或 secret；
- 数据库 `collection_run` 数量、accepted/rejected 数量与 manifest 一致。
