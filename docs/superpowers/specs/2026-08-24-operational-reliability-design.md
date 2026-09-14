# 运行可靠性修复设计

## 目标

消除日报、周报和网站发布的重复执行风险；为每一封未来邮件保留独立、不可覆盖的本地投递记录；并让网站发布具备可审计的主任务与失败补偿机制。

## 已确认事实

- 2026-08-24 周报在 06:00 和 06:04 各运行一次，形成两组各三份 PDF。
- 现有 `Write-MailDeliverySummary` 始终覆盖 `var/reports/YYYY-MM-DD/email-delivery-summary.json`；日报和周报共用该路径，且其中只保存一条总体状态。
- 2026-08-17 仅存一条日报投递摘要，不能据此证明三份周报是否到达邮箱；不重发历史邮件。
- Windows 的日报、周报、网站发布任务与三个 Codex 自动化重叠。Codex 自动化已暂停，Windows 任务是唯一正式入口。
- 旧 `Invoke-ScheduledDailyPipeline.ps1` 使用用户目录中的遗留 PostgreSQL 日志路径。该文件的当前用户 ACL 正常；故障来自遗留启动路径与残留实例状态，而非缺少文件权限。正式启动器使用项目内 `var/postgres`。

## 范围与非目标

范围包括本机 PowerShell 邮件记录、Windows 计划任务、网站发布控制状态、回归测试和维护文档。

不改变 Amazon 采集规则、数据库业务数据、报告内容、网站公开接口或邮件收件人。不会登录邮箱、读取私人收件箱、重新发送 2026-08-17 周报，或把 SMTP 客户端成功错误表述为收件箱实际送达。

## 邮件投递证据

`MailDelivery.psm1` 新增按运行和单封邮件写入的记录接口。日报和周报各自写入：

```text
var/reports/YYYY-MM-DD/delivery/
  daily/<run-id>/manifest.json
  daily/<run-id>/<category>.json
  daily/latest.json
  weekly/<run-id>/manifest.json
  weekly/<run-id>/<category>.json
```

每封记录包含报告种类、类目、报告文件名及 SHA-256、生成时间、收件人、SMTP 处理状态、SMTP 接受时间和已脱敏错误。`manifest.json` 汇总该次三封邮件；`latest.json` 仅是同一报告种类的原子更新索引，不能覆盖另一种报告。

`SENT` 的语义调整为“SMTP 客户端已完成发送调用”，而不是“收件箱已确认接收”。当三封都成功时，运行总状态为 `SENT`；任一封失败时为 `PARTIAL_FAILURE`，且保留成功和失败邮件各自的证据。

日报健康审计只读取同一市场日 `delivery/daily/latest.json`。周报绝不会再影响日报的健康结果。遗留 `email-delivery-summary.json` 保留为历史只读工件，新的流程不再写入它；历史导出继续排除所有投递记录，以避免携带收件人信息。

## 调度与网站发布

Windows 任务是唯一正式运行面：

- `Amazon-BS-Package-Daily-0800`：每天 08:00，`DailyAuto`。
- `Amazon-BS-Package-Weekly-0600`：每周一 06:00，`Weekly`。
- `Amazon-BS-Dashboard-Publish-0900`：每天 09:00，主网站发布。

发布脚本获得本机互斥锁，并在 `var/scheduler/dashboard-publish/YYYY-MM-DD.json` 原子写入 `PUBLISHED` 或 `FAILED` 状态；状态只含市场日、结果、时间、观测数、报告上传数量和脱敏错误。

新增 `Amazon-BS-Dashboard-Publish-Recovery-0915`。它先读取当天状态：主发布已成功时输出 `SKIPPED_ALREADY_PUBLISHED` 并退出 0；状态缺失或失败时才以相同验证门槛调用发布脚本。主任务、恢复任务和人工调用共用互斥锁，避免并发写入。

旧 `Invoke-ScheduledDailyPipeline.ps1` 不再是支持的调度入口，文档与任务注册代码不会再注册它。保留其文件仅为历史兼容，不将其用于自动化。由于 Codex 自动化已暂停，不会再由它触发旧入口。

## 错误处理与可观测性

每个投递记录和发布状态文件均采用“临时文件写入后原子移动”。异常文本继续删除 SMTP、数据库和同步密钥。网站发布的报告上传失败仍披露为数据已发布但报告未完成；主发布失败时由 09:15 补偿处理，补偿失败保留 `FAILED` 状态供人工调查。

Windows Task Scheduler 的 Operational 日志目前未启用，因此不作为唯一审计来源。项目自身的状态文件和转录日志是可移植的运行证据。

## 验收标准

- 日报、周报各产生三条可独立验证的投递记录与一份运行清单，彼此永不覆盖。
- 日报健康审计只读取日报的最新记录。
- 主发布成功时，恢复发布安全跳过；主发布失败时，恢复发布只执行一次。
- Windows 注册结果含四个受控任务，Codex 的三个重叠自动化保持暂停。
- 旧日报入口不再由任何受支持的注册任务调用，且数据库启动日志始终位于项目目录。
- 新增和现有 PowerShell 回归测试通过；不向真实收件人发送测试邮件。
