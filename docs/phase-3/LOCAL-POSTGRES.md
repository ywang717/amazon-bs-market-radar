# 本机 PostgreSQL 开发环境

## 状态

- PostgreSQL：18.4 x64 Windows binaries
- 监听：`127.0.0.1:55432`
- 数据库：`amazon_us_intelligence`
- 用户：`postgres`
- 应用表：32
- 报表视图：7
- 活动来源：3
- 已应用迁移：5
- 当前集成测试：PASSED

## 隔离与安全

- 未注册 Windows 服务，未修改系统 PATH。
- 服务器只监听本机回环地址。
- 密码由加密安全随机数生成器产生，不输出到控制台。
- 本地连接设置位于 `.local/postgres-settings.json`，整个 `.local/` 已被版本控制排除。
- PostgreSQL 二进制和数据目录使用已授权的纯ASCII运行目录，以避开Windows下中文路径代码页问题。

## 生命周期命令

启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Start-LocalPostgres.ps1
```

停止：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Stop-LocalPostgres.ps1
```

应用尚未执行的迁移：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Invoke-LocalMigrations.ps1
```

验证数据库结构：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Test-LocalPostgres.ps1
```

验证真实事务摄取和重复导入幂等性：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Test-PostgresIngestion.ps1
```

## 已验证结果

结构测试：PostgreSQL 18.4、32张应用表、7个视图、3个来源、6个迁移。

摄取测试：同一3条记录的outbox连续执行两次，数据库最终保持：

- `collection_run`：1
- `ranking_observation`：3
- `offer_snapshot`：3
- `listing_snapshot`：3
- `daily_ranking`：3

## 注意事项

- Codex受限沙箱无法创建PostgreSQL服务器的Windows restricted token，因此从Codex启动/停止时可能需要批准在沙箱外执行。用户在普通PowerShell终端运行上述脚本不受该沙箱限制。
- 官方下载归档保留在项目的 `.local/downloads/` 缓存中，受 `.gitignore` 保护。
- 本环境是开发数据库，不是生产部署。生产环境仍需备份、TLS、最小权限角色、监控和恢复目标设计。
