# Phase 3 数据来源决策：Amazon 官方 API

- 状态：Partially accepted
- 核对日期：2026-08-03

## 决策

Search Results 来源优先接入 Amazon Creators API 的 `SearchItems`。PA-API 5 已弃用，不开发新的 PA-API 5 适配器。Best Sellers 与 Movers & Shakers 不使用 Creators API 冒充，因为官方公开的 Creators API 操作集中没有相应专榜操作；这两类来源仍需独立的获准排名提供方。

## 官方依据

- [Creators API Introduction](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/introduction)：当前支持 SearchItems、GetItems、GetVariations 和 GetBrowseNodes，并列出接入前提。
- [PA-API 5 Deprecation Notice](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/paapiv5-deprecation)：PA-API 5 已被 Creators API 取代。
- [Using cURL](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/get-started/using-curl)：NA 使用 LwA OAuth 2.0 client credentials token，API 基址为 `https://creatorsapi.amazon`。
- [SearchItems](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/api-reference/operations/search-items)：单次返回最多 10 个结果，ItemPage 支持 1–10；因此 Top 50 规划为 5 次请求。
- [US Locale Reference](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/locale-reference/united-states)：US marketplace 为 `www.amazon.com`，货币为 USD，并确认 `GardenAndOutdoor` 与 `ToolsAndHomeImprovement` 搜索索引。
- [OffersV2](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/api-reference/resources/offersV2)：提供 featured offer 的价格与 merchant；不再提供旧版的 Amazon fulfillment 字段。

## 字段能力边界

| 平台字段 | Creators API SearchItems |
|---|---|
| ASIN、Title、Brand、Model、URL | 可通过相应资源获得，字段可能缺失 |
| Search position | 由 ItemPage + 页内位置确定，明确标为 SEARCH rank |
| Price、Seller | OffersV2 featured listing |
| FBA Status | OffersV2 不提供旧版 fulfillment 字段，保存 UNKNOWN，不推断 |
| Coupon | 当前适配不提供，保存空值 |
| Rating、Review Count、First Available Date | 当前适配不声称可提供，保存 NULL |
| Best Sellers / Movers & Shakers | 不在此适配器能力范围 |

## 凭证与启用规则

凭证只能由环境变量注入：

- `AMAZON_CREATORS_CLIENT_ID`
- `AMAZON_CREATORS_CLIENT_SECRET`
- `AMAZON_CREATORS_PARTNER_TAG`

示例来源默认 `active=false`。只有在 Associates/Creators API 资格、凭证和用途确认后才允许启用。访问令牌、客户端密钥不得进入日志、manifest、artifact 或代码库。

项目已提供 `scripts/Invoke-CreatorsApiSearch.ps1`。它只读取本地 `config/sources.json`，拒绝未启用来源；该本地配置已从版本控制中排除。Top 50 的五页响应分别归档，随后合并为一个采集批次进入质量门禁。

## 尚未解决

- Creators API 有账户资格和用量限制，项目负责人需确认账户满足要求。
- Browse Node ID 仍为空，后续应通过获准 API 查询并验证后配置。
- Creators API 搜索结果并不保证等同于零个性化网页搜索结果，报告必须标识来源。
- Best Sellers 与 Movers & Shakers 仍需另外确定获准渠道。
