# Amazon US Best Sellers 浏览器采集协议（Top 30）

## 范围

本协议适用于 `config/best-sellers-sources.json` 中的三个公开 Amazon.com Best Sellers 类目。目标是每个类目各自经过验证的**全局排名 1–30**。类目不可混合，搜索结果不可替代 Best Sellers 排名。

仅允许读取公开可见页面：不登录 Amazon、不提交表单、不绕过 CAPTCHA、Robot Check、robots 或访问控制，也不调用未获授权的接口。

| 类目 | Amazon 节点 |
| --- | --- |
| Pressure Washers | `552856` |
| Sump Pumps | `680335011` |
| Pressure Washer Parts & Accessories | `3023451` |

## 采集规则

1. 打开配置中的类目 URL，确认标题、类目节点和页面结构与目标类目一致。
2. 在首屏继续滚动，直到页面实际展示排名 1–30，或确认无法取得完整的连续排名。
3. `PAGINATION_MUST_PRESERVE_GLOBAL_RANKS`：后续页只能用于核验明确延续的全局排名。若排名重置为 1，或无法证明与上一页全局排名连续，则该页不得用于补足 1–30。
4. 对每个可见条目记录 `rank`、`asin`、`title`、`url`、`price`、`rating`、`reviews`。不可见字段为 `null`，不猜测、不从标题推断。
5. 写入 `var/amazon-bestsellers/YYYY-MM-DD/amazon-bestsellers.json`，并由后续回执和质量门槛处理。

## 必须停止的情形

| 情形 | 处理 |
| --- | --- |
| 登录要求、CAPTCHA、Robot Check | 立即停止；不换帐号、不尝试规避。 |
| 标题、节点或页面结构不匹配 | 停止该类目，并记录源异常。 |
| 少于 30 条、排名不连续、重复或超出范围 | 作为不完整/部分结果保留；不宣称完整。 |
| 动态加载失败或零条观察 | 保留状态/工件；自动日常模式不会开始回执、导入、报告、备份或邮件。 |

采集失败不等于可以使用其它页面“补数据”。应保留原始工件和失败原因，待公开页面在合法条件下可见后再重试。

## 数据解释

只有三个类目都通过各自的 Top 30 完整性要求时，才可将该市场日作为完整 Top 30 覆盖解释。实现仍沿用名为 `Test-BestSellersTop50Snapshot` 的历史质量门函数；其当前 Top 30 配置是权威行为，函数名称不表示应收集 Top 50。任何不完整结果都必须在日/周报告中说明受影响类目和可见条数，不能作为完整趋势结论。

本协议描述允许的操作，不是 Amazon 页面当前可访问性或实时数据质量的声明。
