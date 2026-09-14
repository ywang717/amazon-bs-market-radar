# 本地启动器异常功能修复设计

## 目标

修复 `Start-Amazon-BS.bat` 当前不可正常完成的历史导入、既有环境初始化、邮件持久化和 Windows 计划任务功能，同时保持采集、数据库、报告与安全校验的现有约束。

## 范围

### 历史导入与导出

- `Start-LocalPackage.ps1` 新增 `ArchivePath` 与 `OutputPath` 参数。
- `Start-Amazon-BS.bat` 继续通过 `%*` 原样透传参数。
- 非交互模式下，`ImportHistory` 必须要求 `-ArchivePath <zip>`；`ExportHistory` 可选接收 `-OutputPath <zip>`。
- 菜单选择导入历史时询问 ZIP 路径；菜单选择导出历史时使用默认输出位置，不额外打断用户。
- 编排器把路径传给现有稳定脚本，不在编排层解压或恢复数据。
- 默认历史导入只验证归档、哈希、回执和临时恢复演练，不恢复主数据库。

### 恢复演练 JSON 边界

- `Test-LocalPostgresRestoreDrill.ps1` 的标准输出必须只有一个 JSON 对象。
- `CREATE DATABASE`、`DROP DATABASE` 等 `psql` 命令输出必须被抑制，但错误仍通过退出码和异常传播。
- 临时数据库名称继续使用保留前缀，并在成功或失败后清理；不接触生产数据库。

### Setup 复用现有 PostgreSQL

- 新电脑下载 PostgreSQL 或 Chromium 时，仍必须要求清单内的权威 SHA-256 和 `checksum_verified: true`，不得绕过或关闭校验。
- 如果 `.local/postgres-settings.json` 和 `.local/postgres-data/PG_VERSION` 均存在，并且设置指向的 PostgreSQL `initdb.exe` 可验证为要求的 18.4 版本，Setup 应复用该已配置安装，而不是强制要求它位于 `.local/postgresql`。
- 设置与数据标记只存在其中一个、外部安装路径不可读、版本不匹配时，Setup 继续失败并保留现有数据。
- 复用成功后仍运行幂等迁移、验证项目 Python 环境，并选择系统 Edge/Chrome。

### 邮件配置持久化

- 不读取、记录或显示授权码明文。
- 如果当前进程已配置 SMTP 用户名和授权码，而 Windows 当前用户环境尚未配置，则把同一值持久化到 `User` 范围，并验证“已配置”布尔状态。
- 收件人 `746254487@qq.com` 写入 `.local/user-settings.json`，文件只保存收件地址，不保存授权码。
- 不发送测试邮件，最终通过配置状态和后续计划任务参数验证。

### Windows 计划任务

- 注册且仅更新两个固定任务：`Amazon-BS-Package-Daily-0800` 与 `Amazon-BS-Package-Weekly-0900`。
- 时区必须为 `China Standard Time`。
- 日报任务北京时间每日 08:00 执行 `DailyAuto`；周报任务每周一 09:00 执行 `Weekly`。
- 动作必须以项目目录为工作目录，通过 `Start-LocalPackage.ps1` 运行；不得把 SMTP 授权码写入任务参数。
- 重复注册必须幂等，不枚举或删除其他任务。

## 错误处理

- 所有模式继续返回单一机器可读 JSON，并正确传播非零退出码。
- 错误文本继续对 SMTP、`PGPASSWORD` 和数据库密码进行脱敏。
- 历史导入缺少路径时返回明确错误；非法或损坏归档不得提升任何文件。
- Setup 无法验证外部 PostgreSQL 时给出可操作错误，不尝试覆盖现有安装或数据目录。

## 测试与验收

- 先添加会失败的回归测试，再进行最小实现。
- 验证 BAT 可透传 `ArchivePath` 与 `OutputPath`，菜单能收集历史 ZIP 路径。
- 验证恢复演练输出可以直接 `ConvertFrom-Json`。
- 验证 Setup 在现有 PostgreSQL 配置上返回 `READY`，同时保留缺少权威哈希的新安装拒绝测试。
- 完整 Pester 测试必须零失败。
- 实际运行 Setup、历史导出与仅验证导入、邮件持久化检查、计划任务注册与只读核验。
- 最后运行 `Health`；不重复发送日报或周报邮件。

## 非目标

- 不补造 2026-08-04 缺失的历史榜单数据。
- 不恢复或覆盖生产数据库。
- 不关闭下载校验，也不使用未知 SHA-256。
- 不修改 Amazon 公开页面采集规则或报告分析口径。
