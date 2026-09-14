# Best Sellers 快照采集回执

每个浏览器采集快照都必须生成一份 `best-sellers-capture-receipt.json`。回执将快照文件的 SHA-256、来源节点 URL、逐榜单条数、缺失排名、重复项和完整性判定写入同一份可审计记录。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Register-BestSellersSnapshot.ps1 `
  -SnapshotPath .\var\amazon-bestsellers\YYYY-MM-DD\amazon-bestsellers.json
```

状态说明：

- `COMPLETE_VALIDATED`：三个榜单均为连续 Top 50，且快照来源 URL 与配置节点逐一匹配；
- `COMPLETE_SOURCE_METADATA_INCOMPLETE`：数据完整，但来源 URL 元数据缺失或不匹配，不能当作完全可追溯的采集；
- `PARTIAL_NOT_ANALYSIS_ELIGIBLE`：存在缺榜、缺排名、重复或其他完整度问题，保留用于日报披露，但不计入完整市场日。

日报与周报必须保留快照和回执，不得以人工口头说明替代回执。

报告生成前必须重新验证回执：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-BestSellersCaptureReceipt.ps1 `
  -ReceiptPath .\var\amazon-bestsellers\YYYY-MM-DD\best-sellers-capture-receipt.json
```

校验会重新计算快照 SHA-256，并核对市场日和逐榜单完整度。校验失败说明快照与回执不再一致，不能用于排名变化、周度分析或数据库导入。

## 已验证快照入库

以下入口会先验证 capture receipt，再确保本机 PostgreSQL 已启动并执行事务性导入：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Import-VerifiedBestSellersSnapshot.ps1 `
  -SnapshotPath .\var\amazon-bestsellers\<market-date>\amazon-bestsellers.json
```

快照不完整时仍会以实际质量状态追加保存，供日报披露采集覆盖；后续趋势与明显变动分析仍只使用通过 Top 50 完整性门禁的数据。
