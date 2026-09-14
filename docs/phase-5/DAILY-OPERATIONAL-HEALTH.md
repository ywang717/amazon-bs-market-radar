# Best Sellers 每日运行健康审计

日报生成后，使用以下命令核对快照、采集回执、PostgreSQL 历史、PDF 产物和最新数据库备份是否一致：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-BestSellersDailyOperationalHealth.ps1 `
  -MarketDate YYYY-MM-DD
```

健康审计不会把不完整 Top 50 快照当成数据错误；它验证的是快照与回执一致、观测数已按实际数量写入数据库、当天 PDF 已生成，以及最近备份通过归档校验且未超期。任一完整性条件不满足时脚本会失败，供每日自动任务触发失败提醒。
