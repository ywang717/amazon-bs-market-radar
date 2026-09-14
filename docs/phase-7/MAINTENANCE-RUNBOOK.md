# 维护运行手册

> 本节以本地一键包的当前接口为准；早期文档中提到的每日 09:00、Top 50 或独立备份计划不适用于 `Start-Amazon-BS.bat` 的当前菜单流程。

## 本地一键包（当前）

从项目根目录双击 `Start-Amazon-BS.bat`，以中文菜单执行初始化、自动/导入日常处理、周报、健康检查、测试、任务注册和历史迁移。脚本入口为 `scripts\Start-LocalPackage.ps1`，支持 `Menu`、`Setup`、`ConfigureEmail`、`DailyAuto`、`DailyImport`、`Weekly`、`Health`、`Test`、`RegisterTasks`、`ExportHistory` 与 `ImportHistory` 模式。

首次执行 `Setup`。初始化只接受 `config\local-package-runtime-manifest.json` 中含权威 SHA-256 且 `checksum_verified: true` 的 HTTPS 下载；下载先写入临时文件，校验成功后才提升为可用文件。缺少权威校验和、校验不一致、已有目录不完整、组件版本不符，或 PostgreSQL 设置与数据标记不一致时，初始化均会失败并保留已有状态。当前 PostgreSQL 和 Chromium 的清单校验和是占位值，因此这些组件需要下载时，`Setup` 将安全失败，直到维护者提供经验证的清单。

运行时及用户设置放在 `.local\`，虚拟环境在 `.venv\`，快照在 `var\amazon-bestsellers\`，报告在 `var\reports\`。这些目录、数据库数据、凭证与生成工件不应作为源码包内容。

### 日常、周报与计划

- `DailyAuto`：仅采集公开可见 Amazon Best Sellers 页面，目标为每类目全局 Top 30；不登录、不绕过验证码或访问限制。零观察、登录/CAPTCHA/Robot Check、类目异常或排名不连续时失败停止，自动流程不会继续到回执、导入、三份报告、备份或邮件。
- `DailyImport`：必须提供 JSON 快照路径，且 `market_date` 必须是真实日期并与指定日期一致。快照会先安全复制到标准路径，遇到不同内容冲突即失败并保留原文件。
- 每日完整处理的顺序是：登记回执、验证回执、已验证快照导入、三份日报、备份、备份验证、健康审计。任何步骤失败都会返回 `FAILED` 并停止后续步骤。
- `Weekly` 可通过 `-SkipEmail` 生成但不投递周报。`-SkipEmail` 不会跳过其它日常门槛。
- `RegisterTasks` 仅在 Windows 时区为 `China Standard Time` 时注册本地包任务：每天 08:00 执行 `DailyAuto`，每周一 06:00 执行 `Weekly`。注册成功后只会精确移除旧的 `AmazonIntelligence-Daily-0900` 和 `Amazon-BS-Package-Weekly-0900`；不会做广义清理。网站发布任务需单独运行 `scripts\Register-DashboardPublishScheduledTask.ps1 -DashboardUrl <url>`，它会注册 `Amazon-BS-Dashboard-Publish-0900` 与 `Amazon-BS-Dashboard-Publish-Recovery-0915`。四个任务均使用受限的当前交互用户、项目根目录工作目录、120 分钟运行上限（本地包任务）或 `IgnoreNew` 不重叠策略。旧 `Invoke-ScheduledDailyPipeline.ps1` 不再是受支持入口；其用户目录日志路径已弃用，当前 PostgreSQL 运行日志统一保留在项目内 `var\postgres\`。

### 邮件、收件人和秘密

`ConfigureEmail` 以安全提示输入 QQ SMTP 授权码，并保存到当前进程及当前用户的 `DAILY_REPORT_SMTP_USERNAME`、`DAILY_REPORT_SMTP_AUTH_CODE` 环境变量（`-ProcessOnly` 仅当前进程）。不要把授权码写进文件、命令历史、报告、归档或日志。收件人仅保存在 `.local\user-settings.json` 的 `recipient_address` 中，且必须是有效邮箱地址。异常摘要会尝试脱敏 SMTP 和数据库秘密；仍应避免把含秘密的终端输出复制到工单。

### 历史导出/导入

`ExportHistory` 会创建带 SHA-256 清单的 ZIP，包含一个验证过的数据库备份、允许的快照/回执和 PDF、HTML、Markdown 报告；秘密、浏览器/缓存/临时/日志文件和敏感配置被排除。此操作会创建备份，必须在合适的维护窗口执行。

`ImportHistory` 先私有复制，再验证归档身份、路径、清单、校验和、备份、临时恢复演练和快照回执，随后安全提升快照/回执/报告。默认不恢复主数据库（`VALIDATED_NOT_RESTORED`）。只有直接运行导入脚本并显式添加 `-RestoreDatabase`，且目标主数据库为空时才会恢复；恢复前需备份并获得明确授权。

项目功能开发已收尾，后续以“监测、核验、修复”为原则运行。所有市场结论仍须受真实数据完整度门禁约束。

## 已启用的日常保障

- `Amazon-BS-Package-Daily-0800`：每天北京时间 08:00 运行 `DailyAuto`，执行采集、回执、导入、三份日报、备份、备份验证和健康审计。
- `Amazon-BS-Package-Weekly-0600`：每周一北京时间 06:00 运行 `Weekly`，在覆盖不足时只输出有限分析并明确标记。
- `Amazon-BS-Dashboard-Publish-0900`：每天北京时间 09:00 发布已验证的网站数据。
- `Amazon-BS-Dashboard-Publish-Recovery-0915`：每天北京时间 09:15 检查当天发布状态；主发布已成功时返回 `SKIPPED_ALREADY_PUBLISHED`，缺失或失败时补偿一次。
- 与上述流程重叠的三个 Codex 自动化已暂停，不应作为当前运维入口或成功证据。

## 问题处置顺序

1. 运行健康审计，确认是采集、回执、数据库、报告还是备份环节异常；
2. 保留原始快照、回执、日志和失败输出，不删除历史证据；
3. 修复后使用同一输入重新运行，并确认导入幂等、不会制造重复记录；
4. 执行完整测试套件；涉及数据库备份/恢复逻辑时，还要执行隔离恢复演练；
5. 在运行手册或检查点中记录根因、修复和验证结果。

## 常用检查命令

```powershell
# 全量回归
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1

# 指定市场日的端到端健康检查
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-BestSellersDailyOperationalHealth.ps1 `
  -MarketDate YYYY-MM-DD

# 验证某一逻辑备份（不恢复）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Test-LocalPostgresBackup.ps1 `
  -BackupPath .\.local\postgres-backups\amazon-us-intelligence-<timestamp>.dump
```

## 维护边界

- 不绕过 Amazon 登录、验证码、robots 或访问限制；
- 不把不完整 Top 50、搜索结果或缺失字段包装成完整趋势；
- 不删除历史快照、原始 artifact 或备份作为“修复”手段；
- 恢复操作只在隔离数据库演练或获得明确授权后执行；
- 密码、SMTP 授权码与 API 凭证只保存在用户环境变量或本机受控设置中，不能写入项目文件或报告。

## 价格完整性恢复

当榜单条目的价格缺失时，采集器会访问公开商品详情页核验，并且只记录以下四种原因码之一：

- `DETAIL_PRICE_FOUND`：详情页存在公开价格；该价格会补充到本次观察。
- `PRICE_NOT_PUBLIC`：有受支持的公开证据表明价格不可用、商品缺货、没有精选报价、只能查看全部购买选项或登录后才能查看价格。只有此原因允许快照保留空价格。
- `VERIFICATION_BLOCKED`：Amazon 显示 CAPTCHA、登录、Robot Check、拒绝访问或其它访问控制。不得绕过。
- `PRICE_MISSING_UNEXPLAINED`：页面可以读取，但既没有公开价格，也没有受支持的缺价解释。

一次实时采集最多进行三次完整尝试：首次尝试加最多两次重试。每次重试都使用全新的临时浏览器会话并重新采集全部启用类目；不得合并不同尝试的数据。只有每个类目都恰好包含第 1 至 30 名、必填字段完整、类目内 ASIN 唯一，并且每个空价格都有 `PRICE_NOT_PUBLIC` 证据时，该尝试才可发布。

对于市场日期 `YYYY-MM-DD`，检查 `var\amazon-bestsellers\YYYY-MM-DD\` 下的本地工件：

- `amazon-bestsellers.json`：标准快照；只有完整性验证通过后才会写入或替换。
- `best-sellers-collection-status.json`：最新采集状态和安全的控制字段。
- `price-completeness-diagnostic.json`：经过脱敏的尝试摘要、价格证据和安全失败原因码。

如果三次尝试全部失败，`CompletenessStatus` 为 `FAILED`，失败尝试不会发布为标准快照，`DailyAuto` 会在采集后停止。不得继续登记回执、导入数据库、生成日报、备份、健康审计或发送邮件。保留状态和诊断工件供调查；不得把旧的标准快照当成本次运行成功。

## 当前榜单发布、优惠字段与入库

当前交易日只允许在采集控制状态和三项类目结果均为精确的 `COMPLETE` 时发布标准快照。发布前必须确认每个类目均有唯一 ASIN 的全局排名 1–30；`INCOMPLETE`、`FAILED`、缺失控制工件或任一类目不满足此条件时，不能登记回执、不能导入 PostgreSQL、不能用旧快照代替本次结果，也不能生成或发送报告。

公开优惠字段的含义必须按三态解释：`has_discount=true` 表示公开商品详情页已核实存在优惠，`false` 表示已核实无优惠，`null`（报告中显示“等待核验”）表示公开页面无法核验。这一未知状态不是“无优惠”，`discounts=[]` 也不把未知改写为无优惠。优惠核验只使用公开页面；遇到登录、验证码、拒绝访问或页面不可用时停止核验，不登录、不绕过，并仅保留已脱敏的结构化原因。

对通过 COMPLETE 门禁的快照，先运行 `Register-BestSellersSnapshot.ps1` 生成回执，再用 `Test-BestSellersCaptureReceipt.ps1` 验证回执、市场日、来源元数据和快照 SHA-256。只有验证结果 `valid=true` 的快照可通过 `Import-VerifiedBestSellersSnapshot.ps1` 导入 PostgreSQL。导入后应抽查代表性 ASIN 的类目、排名、评分、评论数、优惠状态及优惠列表，与快照和数据库当前视图一致。

日报和周报在本地验收或人工维护时必须显式传入 `-SkipEmail`；该参数会在输出中产生 `SKIPPED_BY_REQUEST` 的投递状态，且不会发送邮件。自动投递结果中的 `SENT` 仅表示 SMTP 客户端已完成发送调用，不代表收件箱已确认收件；要核验未来邮件，请查看 `var\reports\YYYY-MM-DD\delivery\` 下按运行和按邮件保留的记录。生成后抽查同一代表性 ASIN 在快照、数据库、Markdown、HTML 和 PDF 中的字段一致性。若采集未达到 COMPLETE，停止在安全诊断阶段，不导入、不报告且不发送邮件。

人工调查时，只检查脱敏后的状态/诊断字段、投递记录和公开榜单页或商品页。不得把 Cookie、凭证、浏览器配置文件、完整页面正文或敏感终端输出复制到工单；不得登录、解决或绕过 CAPTCHA、规避访问控制或引入凭证。如果 Amazon 标记结构发生变化，应使用脱敏证据复现问题，新增或更新自动化测试，在源代码管理中修改选择器，运行完整测试套件，检查差异并部署经过测试的提交。不得在计划任务运行期间直接编辑采集器源代码或选择器。
