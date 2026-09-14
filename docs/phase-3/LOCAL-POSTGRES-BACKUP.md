# 本机 PostgreSQL 逻辑备份

项目提供可验证的 PostgreSQL 自定义格式逻辑备份，用于保护本机采集、排名历史和报告数据。

## 创建备份

在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\postgres\Backup-LocalPostgres.ps1
```

备份文件会写入 `.local\postgres-backups\`，命名包含 UTC 时间戳。每个 `.dump` 同时生成同名的 `.dump.json` 清单，其中记录：

- 数据库与生成时间；
- 文件大小；
- SHA-256 完整性摘要；
- 备份工具与格式版本。

备份采用 PostgreSQL custom archive 格式，便于在需要时选择性恢复。清单不会记录数据库密码或 SMTP 凭据。

## 非破坏性验证

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\postgres\Test-LocalPostgresBackup.ps1 `
  -BackupPath .\.local\postgres-backups\amazon-us-intelligence-<timestamp>.dump
```

验证会重新计算 SHA-256，并调用 `pg_restore --list` 检查归档目录；该过程不会向任何数据库写入或执行恢复。

## 恢复准备

在真正恢复前，先在隔离的 PostgreSQL 数据库中验证备份和恢复步骤。生产数据恢复属于显式运维操作，项目脚本不会自动执行，避免误覆盖现有数据。

`.local` 仅适合作为本机短期存放位置。请定期将已验证的备份复制到受加密保护的外部存储或企业备份系统，以防电脑故障或磁盘损坏。

## 每日自动备份

默认在本机时区每天 10:30 运行；该时间安排在 09:00 的日报采集与发送之后，且任务设置为忽略重叠运行。注册或更新任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Register-LocalPostgresBackupScheduledTask.ps1
```

任务仅在当前 Windows 用户已登录时运行，并只执行逻辑备份，不会恢复、清理或删除任何数据库数据。可用 `-DailyAt '11:00'` 调整执行时间。

## 隔离恢复演练

可定期在自动生成的临时数据库中执行完整恢复演练：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Test-LocalPostgresRestoreDrill.ps1 `
  -BackupPath .\.local\postgres-backups\amazon-us-intelligence-<timestamp>.dump
```

脚本先验证归档和 SHA-256，再创建名称以 `amazon_intelligence_restore_` 开头的临时数据库，还原并检查关键业务表。演练结束后自动删除**仅该临时数据库**；生产数据库 `amazon_us_intelligence` 永远不会被作为恢复目标。若需人工检查演练库，可显式使用 `-KeepRestoreDatabase`，检查结束后再由管理员删除。
