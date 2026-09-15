# Amazon US Best Sellers 本地情报包

这是一个面向 Amazon.com 美国站的本地 Windows 工具包。唯一的可见入口是根目录的 `Start-Amazon-BS.bat`；它会启动 PowerShell 菜单并把可变运行时和数据保留在项目目录内。

在 macOS 上使用 `Start-Amazon-BS-macos.sh`。macOS 不支持 Windows Task Scheduler；需要定时运行时，请将 `config/macos.launchd.plist.example` 中的 `PROJECT_ROOT` 替换为项目绝对路径后复制到 `~/Library/LaunchAgents/`，再执行 `launchctl load`。采集脚本仍依赖项目内 PowerShell、PostgreSQL 和 Chromium 运行时。

## macOS 使用说明

支持 macOS 12 或更高版本（Apple Silicon 和 Intel）。先安装 Homebrew，然后安装运行时：

```bash
brew install node powershell postgresql@16
cd "/Users/你的用户名/Documents/亚马逊bestseller榜单监控"
./scripts/install-macos-runtime.sh
cd web
npm install
npm exec playwright install chromium
```

回到项目根目录启动：

```bash
cd "/Users/你的用户名/Documents/亚马逊bestseller榜单监控"
chmod +x Start-Amazon-BS-macos.sh
./Start-Amazon-BS-macos.sh
```

首次运行建议使用测试模式：

```bash
./Start-Amazon-BS-macos.sh -Mode Test
```

日常采集、导入和健康检查示例：

```bash
./Start-Amazon-BS-macos.sh -Mode DailyAuto -MarketDate 2026-08-12
./Start-Amazon-BS-macos.sh -Mode DailyImport -SnapshotPath "/绝对路径/amazon-bestsellers.json" -SkipEmail
./Start-Amazon-BS-macos.sh -Mode Health -MarketDate 2026-08-12
```

macOS 使用 `launchd` 定时运行，不使用 Windows 计划任务。复制 `config/macos.launchd.plist.example`，将其中每个 `PROJECT_ROOT` 替换为项目绝对路径，再加载任务：

```bash
mkdir -p "$HOME/Library/LaunchAgents"
sed "s#PROJECT_ROOT#$(pwd)#g" config/macos.launchd.plist.example > "$HOME/Library/LaunchAgents/com.amazon-bs.daily.plist"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.amazon-bs.daily.plist"
```

如果出现 `env: node: No such file or directory`，请确认当前终端已加载 Homebrew 路径（Apple Silicon 通常是 `/opt/homebrew/bin`），或重新执行启动脚本；脚本会自动搜索 Homebrew 和系统 `pwsh`。

本仓库不包含已下载的运行时、浏览器、数据库、报告、快照或任何凭证。下文描述的是本地操作约定，不代表本仓库已经执行过浏览器采集、邮件投递、安装、计划任务注册或外部服务集成。

## 开始使用

在 Windows 10/11 x64 上双击 `Start-Amazon-BS.bat`。也可从 PowerShell 显式运行某个模式：

```powershell
.\Start-Amazon-BS.bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-LocalPackage.ps1 -Mode Test
```

首次使用时，在菜单中选择 **4. 初始化本地环境**。初始化会验证运行时清单、项目内 Python/PostgreSQL、虚拟环境、数据库迁移以及浏览器选择；它不需要管理员权限。只有成功返回 `READY` 后，才应继续运行采集或计划任务。

当前清单中的 PostgreSQL 与 Playwright Chromium 尚未记录权威 SHA-256（值为占位符），因此需要下载这两个组件时，初始化会故意失败并且不会下载或安装。请先由受信任的维护者更新 `config/local-package-runtime-manifest.json` 中相应的 HTTPS 来源、SHA-256 和 `checksum_verified: true`，再重试。不要通过关闭校验、替换为未知校验和或手动移动不明下载文件来绕过此限制。

## 菜单与命令模式

`Start-Amazon-BS.bat` 不带参数时显示中文菜单：

| 菜单 | 模式 | 用途 |
| --- | --- | --- |
| 1 | `DailyAuto` | 使用可见浏览器自动采集，并在所有门槛通过后执行日常处理。 |
| 2 | `DailyImport` | 导入已有 JSON 快照；菜单会询问快照路径。 |
| 3 | `Weekly` | 生成周报。 |
| 4 | `Setup` | 初始化/验证项目内运行环境。 |
| 5 | `ConfigureEmail` | 交互式配置 QQ SMTP 发件帐号和授权码。 |
| 6 | `Health` | 对指定或默认市场日运行健康审计。 |
| 7 | `Test` | 运行项目测试入口。 |
| 8 | `RegisterTasks` | 注册本地 Windows 计划任务。 |
| 9 | `ExportHistory` | 导出可迁移的历史归档。 |
| 10 | `ImportHistory` | 验证并导入历史归档。 |
| 0 | `Exit` | 退出菜单。 |

非交互模式示例：

```powershell
# 自动采集（实际运行会打开浏览器，并可能继续执行数据库、报告、备份和邮件步骤）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-LocalPackage.ps1 -Mode DailyAuto -MarketDate 2026-08-11

# 导入一个已有快照；市场日必须与 JSON 中的 market_date 一致
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-LocalPackage.ps1 -Mode DailyImport `
  -SnapshotPath C:\path\to\amazon-bestsellers.json -SkipEmail

# 生成周报但不投递邮件
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-LocalPackage.ps1 -Mode Weekly -SkipEmail
```

`-SkipEmail` 仅跳过邮件投递；它不会跳过采集、数据库、报告、备份或健康检查。并发运行同一种模式会被项目内 `.local\locks\` 锁拒绝。

## Top 30 合规浏览器采集

采集对象仅限 `config/best-sellers-sources.json` 配置的三个公开 Amazon Best Sellers 类目：Pressure Washers、Sump Pumps 和 Pressure Washer Parts & Accessories。每个类目独立采集和验证，目标是经页面明确显示的全局排名 1–30。

- 只读取公开可见页面；绝不登录、提交表单、绕过 CAPTCHA/Robot Check、robots 或访问控制，也不使用未获授权的接口。
- 页面标题、类目节点和结构必须与配置一致。出现登录页、Robot Check、CAPTCHA 或类目不匹配时，停止该类目并记录失败状态。
- 可在首屏继续滚动以获得 1–30。只有后续页面明确保留连续的全局排名时才可检查或采集；若排名从 1 重新开始，或连续性无法验证，后续页不得用于补足 Top 30。
- 每条记录保留可见的 `rank`、`asin`、`title`、`url`、`price`、`rating` 和 `reviews`。页面未显示的值写入 `null`，绝不推测或补全。
- 缺失、重复或不连续排名，动态加载失败，或零条观察结果都不会被包装为完整数据。自动模式在零条观察时会停止，且不会启动回执、导入、报告、备份或邮件。

快照写入 `var\amazon-bestsellers\YYYY-MM-DD\amazon-bestsellers.json`。日常完整处理依次要求：回执登记和验证、已验证快照的事务导入、三份日报、备份及备份验证、健康审计。任一步失败即返回 `FAILED`，后续步骤不会继续。详情见 [浏览器采集协议](docs/phase-3/BEST-SELLERS-BROWSER-COLLECTION-PROTOCOL.md)。

## 卖家经营情报与网站发布

网站发布器只会在日常健康审计返回 `HEALTHY` 后，基于已验证回执的快照生成并同步 4 份 `seller_alert` 日报；若当日已有既有周报 JSON，再额外生成并同步 4 份 `competition_strategy` 周报。同步接口仅接受 `imported` 或 `duplicate`；生成或同步失败只把网站发布标为失败，不修改或阻断本机采集、PDF、邮件、数据库或备份流程。

- 经营预警只在当前和相邻前一日都为精确、连续且去重的 Top 30 时输出可比较变化；不完整数据仅给出质量披露和可见排名事实。
- 价格、星级、评论、优惠任一字段的覆盖率低于 80% 时，暂停该字段对应的描述性观察；不会把缺失值当作 0 或“无”。
- 竞争策略、竞品池和稳定趋势至少需要 5 个完整市场日；不足时明确显示数据积累中，而不输出稳定趋势结论。
- 标题中不能明确验证的规格、品牌或兼容性一律为 `null`，页面和报告不以 0、空字符串或推测值替代。
- “待核查”表示下一步人工核验价格、优惠、评分、评论或标题规格的提示；它是非因果的描述性观察，不代表销量、利润或选品成功预测。

## 邮件与收件人

菜单项 5 会安全地提示输入 QQ SMTP 授权码，并将 `DAILY_REPORT_SMTP_USERNAME` 与 `DAILY_REPORT_SMTP_AUTH_CODE` 写入当前进程和当前 Windows 用户的环境变量；授权码不会写入项目文件、报告、归档或正常摘要输出。可用 `-ProcessOnly` 仅写入当前 PowerShell 进程。

收件人地址保存在 `.local\user-settings.json` 的 `recipient_address` 字段中，可在初始化时提供 `-RecipientAddress`，或由本地设置管理。地址必须是有效邮箱格式。未配置收件人时，流水线不会从项目文件猜测地址；邮件投递需要明确配置及有效 SMTP 环境变量。

SENT means the local SMTP client completed the send call and does not confirm inbox delivery.

## 计划任务

在 **Windows 时区恰好为 `China Standard Time`** 时，菜单项 8 才能注册本地包任务；其它时区会失败而不注册。当前受支持的四个 Windows 任务为：

- `Amazon-BS-Package-Daily-0800`：每天 08:00（中国标准时间），运行 `DailyAuto`；注册成功后仅精确移除旧的 `AmazonIntelligence-Daily-0900`。
- `Amazon-BS-Package-Weekly-0600`：每周一 06:00（中国标准时间），运行 `Weekly`；注册成功后仅精确移除旧的 `Amazon-BS-Package-Weekly-0900`。
- `Amazon-BS-Dashboard-Publish-0900`：每天 09:00，运行 `scripts\Publish-BestSellersDashboard.ps1` 发布网站。
- `Amazon-BS-Dashboard-Publish-Recovery-0915`：每天 09:15，运行 `scripts\Invoke-DashboardPublishRecovery.ps1`，仅在主发布缺失或失败时补偿。

前两个任务由菜单项 8 调用 `scripts\Register-LocalPackageScheduledTasks.ps1` 注册；后两个任务需要单独运行 `scripts\Register-DashboardPublishScheduledTask.ps1 -DashboardUrl <url>`。四个任务都使用当前交互式 Windows 用户、受限权限、项目根目录为工作目录，并以 `IgnoreNew` 防止同名任务重叠。`Invoke-ScheduledDailyPipeline.ps1` 已退役，不会再被任何受支持的计划任务注册；其旧日志路径也不再使用，当前 PostgreSQL 运行日志保留在项目内 `var\postgres\`。Codex 中与这些任务重叠的三个自动化已暂停，Windows 任务是唯一正式调度入口。注册计划任务会更改本机任务计划程序，仅在确认配置完成后执行。

## 可携带数据与历史迁移

所有可变运行时和用户设置均位于 `.local\`；Python 虚拟环境位于 `.venv\`；快照位于 `var\amazon-bestsellers\`；报告位于 `var\reports\`。这些目录和生成的数据库文件不应被打包进源码发布物。

`ExportHistory` 创建含 SHA-256 清单的 ZIP：一个已验证数据库逻辑备份、合格快照及其采集回执、以及筛选后的 `.pdf`/`.html`/`.md` 报告。凭证、SMTP 设置、环境配置、浏览器缓存、日志和临时文件会被排除。

`ImportHistory` 会先在私有暂存目录复制归档，再校验路径、清单、SHA-256、备份和临时数据库恢复演练、以及每份快照回执。默认只验证并原子化导入快照/回执/报告，状态为 `VALIDATED_NOT_RESTORED`；它不会恢复主数据库。只有直接调用导入脚本并显式加上 `-RestoreDatabase`，且主数据库为空时，才会恢复数据库。不要在未备份且未获明确授权的环境中执行恢复。

## 安全验证

以下检查不应联系 Amazon、发送邮件、注册计划任务、导入/导出历史、备份/恢复或修改数据库：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-LocalPackage.ps1 -Mode Test
```

测试夹具位于 `tests\fixtures\`，仅用于本地验证，并不表示真实 Amazon 采集结果。

## 故障处理

保留原始快照、回执、报告和失败摘要，不要通过删除历史证据来“修复”。先运行 `Health` 或 `Test` 以定位采集、回执、数据库、报告、备份或配置问题；修复后可用同一输入重试，导入流程是幂等保护的。发现 CAPTCHA、登录要求或类目/排名不连续时，应等待合法、人工可见的条件恢复，而不是规避限制。更多维护步骤见 [本地包维护手册](docs/phase-7/MAINTENANCE-RUNBOOK.md)。
