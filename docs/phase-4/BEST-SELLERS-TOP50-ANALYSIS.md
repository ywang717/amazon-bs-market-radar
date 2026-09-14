# Best Sellers Top 50 排名变化分析

## 目标

对浏览器采集的三个 Amazon Best Sellers 榜单快照执行独立质量门禁和日排名比较，避免将 Search、Creators API 和 Best Sellers 三种来源口径混用。

监控节点：

- Pressure Washers：`552856`；
- Sump Pumps：`680335011`；
- Pressure Washer Parts & Accessories：`3023451`。

## 输入

每日原始快照：

`var/amazon-bestsellers/YYYY-MM-DD/amazon-bestsellers.json`

每个类目应包含排名 1–50，并保存 ASIN、标题、价格、评分、评论数、URL、来源页码和采集时间。Amazon 第一页需要继续滚动加载第31–50名；`pg=2` 从第51名开始，不能用于补齐前50。

## 质量门禁

- 每个类目恰好 50 条；
- 排名 1–50 连续；
- ASIN 唯一；
- 排名唯一；
- ASIN 不为空；
- 少于 50 条时默认失败；只有 Amazon 页面实际不足或分页失败并需要保留证据时，才使用 `-AllowIncomplete`。

## 波动规则

`rank_change = previous_rank - current_rank`，正数表示上升。

- `abs(rank_change) >= 10`：WATCH；
- `abs(rank_change) >= 20`：HIGH；
- 新进入前 50：NEW_IN_TOP50 / IMPORTANT；
- 退出前 50：DROPPED_FROM_TOP50 / IMPORTANT；
- 首次成功快照：BASELINE，不产生虚假波动信号。
- 新增榜单按类目独立建立 BASELINE，不把整榜误报为 NEW_IN_TOP50。

## 运行

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Analyze-BestSellersSnapshot.ps1 `
  -CurrentPath .\var\amazon-bestsellers\2026-08-05\amazon-bestsellers.json `
  -PreviousPath .\var\amazon-bestsellers\2026-08-04\amazon-bestsellers.json
```

输出文件位于当日快照目录：`best-sellers-analysis.json`。中文报告必须读取其中的 `quality` 和 `analysis.noteworthy`，不能自行猜测排名变化。

日报和周报的用户可见文件名必须包含北京时间标记：`YYYY-MM-DD_HHmm_BJT`；标题和正文元数据使用“北京时间 YYYY-MM-DD HH:mm”，并标注 `Asia/Shanghai / UTC+08:00`。

## PostgreSQL 历史入库

完成快照质量分析后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\postgres\Import-BestSellersSnapshot.ps1 `
  -ArtifactPath .\var\amazon-bestsellers\2026-08-05\amazon-bestsellers.json
```

迁移 `007_best_sellers_history.sql` 提供：

- 追加式快照运行与三榜单来源运行；
- ASIN、排名、价格、评分和评论数历史；
- 基于文件 SHA-256 的重复导入幂等；
- `best_sellers_daily_current`、`best_sellers_daily_change` 和 `best_sellers_daily_exit` 视图。
