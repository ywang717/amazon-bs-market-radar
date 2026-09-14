# Amazon US Best Sellers 中文周报 PDF

周报在每周一北京时间 09:00 运行。它使用三个独立 Best Sellers 榜单快照，并先执行 `Test-Phase5AnalysisReadiness.ps1` 判断覆盖状态。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-BestSellersWeeklyReport.ps1
```

默认生成中文 Markdown、HTML 和经渲染验证的 PDF，并将 PDF 发送至 `746254487@qq.com`；文件名和邮件标题均含北京时间。调试时添加 `-SkipEmail`。

规则如下：

- 2026-08-10 起，即使覆盖不足，也生成首次有限周度分析，并明确标注为初始基线；
- 三个榜单均积累 8 个完整 Top 50 市场日后，才将结果标记为完整周度分析；
- 机会、市场结构、价格/星级/评论数关联仅在周报中生成；
- 不完整快照不作为完整 Top 50、趋势或因果结论的依据。
