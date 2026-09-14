# Amazon US Best Sellers 中文日报 PDF

日报使用三个独立 Best Sellers 快照，不读取或混用 Creators API Search 结果。它只记录采集完整度和已验证的明显排名变化：当前、上一市场日的同一榜单都必须通过完整 Top 50 校验，才会展示排名变动、新入榜或退出榜单。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-BestSellersDailyReport.ps1 `
  -CurrentPath .\var\amazon-bestsellers\YYYY-MM-DD\amazon-bestsellers.json `
  -PreviousPath .\var\amazon-bestsellers\YYYY-MM-DD\amazon-bestsellers.json
```

脚本会生成中文 Markdown、HTML 和经渲染验证的 PDF，文件名和邮件标题均包含北京时间；默认将 PDF 发送至 `746254487@qq.com`。调试时添加 `-SkipEmail`。

没有上一日快照或任何榜单不完整时，仍会生成 PDF，但只披露基线或采集缺口，不输出不可靠的变化判断。当天与上一天均完整时，绝对排名变化达到 10 名会标为关注，达到 20 名会标为高优先级；新入和退出 Top 50 也会提示。
