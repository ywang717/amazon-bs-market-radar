# Phase 2 — 数据库与逻辑数据模型设计

数据库逻辑名称：`Amazon_US_Intelligence_Database`。本文件是逻辑设计，不包含可执行 DDL 或 ORM 模型。

## 1. 建模原则

- 使用内部稳定 ID 建立关系，ASIN 作为 marketplace 范围内的业务标识。
- 事实表追加写入；产品主数据更新保留变更审计。
- 原始值与规范值并存，例如 `brand_raw` 与 `brand_id`。
- `observed_at` 使用 UTC 时间戳，`market_date` 使用 Amazon US 对应的太平洋市场日。
- 金额使用定点小数并显式保存货币，禁止浮点存价格。
- 未知值使用 NULL 和质量标志，不用空字符串、0 或虚构值代替。

## 2. 实体关系概览

```text
marketplace 1─N category 1─N source_definition
category   1─N category (parent-child)
brand      1─N product N─1 marketplace
product    1─N ranking_observation N─1 collection_run
product    1─N offer_snapshot       N─1 collection_run
product    1─N listing_snapshot     N─1 collection_run
product    1─N daily_product_metric
product    1─N detection_signal
brand      1─N daily_brand_metric
score_model_version 1─N opportunity_score
```

## 3. 核心表

### 3.1 维度与配置

| 表 | 关键字段与类型 | 用途与约束 |
|---|---|---|
| `marketplace` | `marketplace_id UUID/BigInt PK`, `code varchar`, `country_code char(2)`, `currency char(3)`, `timezone varchar` | `code` 唯一；首条为 Amazon US |
| `category` | `category_id PK`, `parent_category_id FK nullable`, `name varchar`, `slug varchar`, `category_level smallint`, `accessory_type varchar nullable`, `active boolean` | 自引用品类树；`slug` 唯一；支持任意新品类 |
| `category_source_map` | `marketplace_id FK`, `external_node_id varchar`, `category_id FK`, `valid_from date`, `valid_to date nullable` | Amazon 节点到规范品类的时态映射 |
| `source_definition` | `source_id PK`, `marketplace_id FK`, `category_id FK`, `source_type enum`, `search_term varchar nullable`, `target_limit int`, `config_json json`, `active boolean` | 类型为 BEST_SELLERS、MOVERS_SHAKERS、SEARCH；搜索源必须有搜索词 |
| `brand` | `brand_id PK`, `canonical_name varchar`, `normalized_key varchar`, `created_at timestamptz` | `normalized_key` 唯一；品牌合并需审计 |
| `brand_alias` | `alias_normalized varchar`, `brand_id FK`, `valid_from`, `valid_to nullable` | 保留品牌归一历史 |
| `seller` | `seller_id PK`, `marketplace_id FK`, `external_seller_id varchar nullable`, `display_name varchar`, `normalized_key varchar` | marketplace 内业务键唯一 |

### 3.2 产品与运行审计

| 表 | 关键字段与类型 | 用途与约束 |
|---|---|---|
| `product` | `product_id PK`, `marketplace_id FK`, `asin char(10)`, `brand_id FK nullable`, `model varchar nullable`, `first_seen_at timestamptz`, `last_seen_at timestamptz`, `status varchar` | `(marketplace_id, asin)` 唯一 |
| `product_category` | `product_id FK`, `category_id FK`, `valid_from date`, `valid_to date nullable`, `confidence decimal`, `mapping_method varchar` | 产品可属于多个品类，映射可随时间演进 |
| `collection_run` | `run_id UUID PK`, `source_id FK`, `started_at`, `finished_at`, `status`, `parser_version`, `expected_count`, `raw_count`, `accepted_count`, `rejected_count`, `error_summary` | 一次源任务的完整审计 |
| `raw_artifact` | `artifact_id PK`, `run_id FK`, `content_hash char(64)`, `storage_uri varchar`, `captured_at`, `media_type`, `retention_status` | 原始载荷外部存储索引；内容指纹防重复 |
| `data_quality_issue` | `issue_id PK`, `run_id FK`, `record_locator varchar`, `rule_code`, `severity`, `details_json`, `created_at`, `resolution_status` | 隔离错误和修正记录 |

### 3.3 追加式历史事实

| 表 | 关键字段与类型 | 用途与约束 |
|---|---|---|
| `ranking_observation` | `observation_id PK`, `run_id FK`, `market_date date`, `observed_at timestamptz`, `source_id FK`, `category_id FK`, `product_id FK`, `rank int`, `source_badge varchar nullable`, `page_position int nullable`, `source_url varchar` | 唯一键建议 `(run_id, source_id, category_id, product_id)`；`rank > 0` |
| `offer_snapshot` | `offer_snapshot_id PK`, `run_id FK`, `product_id FK`, `market_date`, `observed_at`, `price decimal(12,2) nullable`, `currency char(3)`, `coupon_text varchar nullable`, `coupon_value decimal nullable`, `seller_id FK nullable`, `fba_status enum`, `availability varchar nullable` | 保留 Price、Coupon、Seller、FBA 的每日变化 |
| `listing_snapshot` | `listing_snapshot_id PK`, `run_id FK`, `product_id FK`, `market_date`, `observed_at`, `title text`, `model varchar nullable`, `rating decimal(2,1) nullable`, `review_count int nullable`, `first_available_date date nullable`, `canonical_url varchar`, `content_hash char(64)` | 内容相同可引用前版以减少存储，但不能破坏历史可追溯性 |
| `listing_content_snapshot` | `listing_snapshot_id FK`, `bullet_points json/array`, `image_refs json`, `description text nullable` | Phase 5 Listing 分析所需内容，是否采集须先确认合规与可用性 |
| `review_snapshot` | `review_snapshot_id PK`, `run_id FK`, `product_id FK`, `review_external_id varchar nullable`, `rating smallint`, `review_date date`, `title text`, `body text`, `verified boolean nullable`, `content_hash char(64)` | TOP20 正/负评论分析输入；保留最小必要数据和来源审计 |

## 4. 派生指标与信号表

| 表 | 关键字段与类型 | 说明 |
|---|---|---|
| `daily_product_metric` | `market_date`, `product_id`, `category_id`, `source_id`, `current_rank`, `previous_rank nullable`, `rank_change nullable`, `price`, `rating`, `review_count`, `review_velocity_7d/30d`, `coverage_days`, `calculation_version` | `rank_change = previous_rank - current_rank`，正数表示提升 |
| `daily_brand_metric` | `market_date`, `brand_id`, `category_id`, `product_count`, `top100_count`, `rank_share`, `growth_7d/30d/90d`, `calculation_version` | 品牌趋势和 Brand Growth 输入 |
| `detection_signal` | `signal_id`, `market_date`, `signal_type`, `product_id nullable`, `brand_id nullable`, `category_id`, `severity`, `evidence_json`, `rule_version`, `created_at` | 新品、新品牌、上升、低竞争等可追溯事件 |
| `score_model_version` | `model_version PK`, `effective_from`, `weights_json`, `thresholds_json`, `missing_policy_json`, `status` | 评分权重和阈值版本化 |
| `opportunity_score` | `market_date`, `product_id`, `category_id`, `model_version FK`, 五个分项, `total_score`, `level`, `evidence_json` | 结果可重现；唯一键含模型版本 |

## 5. 原提示字段映射

| 要求字段 | 存储位置 |
|---|---|
| Date | 各事实表的 `market_date` |
| Category / Sub Category / Accessory Type | `category` + `product_category` |
| Rank | `ranking_observation.rank` |
| Previous Rank / Rank Change | `daily_product_metric`，从同源相邻有效市场日派生 |
| Product Title / Model Number / URL | `listing_snapshot` |
| Brand | `brand`、`brand_alias`，并保留采集原值于解析暂存数据 |
| ASIN | `product.asin` |
| Price / Coupon / Seller / FBA Status | `offer_snapshot` |
| Rating / Review Count / First Available Date | `listing_snapshot` |

特别说明：主指令 PART 6 包含 `Coupon`，PART 7 的简表遗漏该字段。本设计保留 Coupon，避免信息损失。

## 6. 更新与历史策略

1. 采集开始前创建 `collection_run`。
2. 原始载荷落地并生成 SHA-256 指纹。
3. 验证通过后 upsert 稳定维度，事实快照只 insert。
4. 同一 `run_id` 重放以业务唯一键幂等，不重复插入。
5. 运行完成后基于相邻有效市场日计算 Previous Rank 和 Rank Change。
6. 信号与分数记录规则版本；规则变化可重算并并存新版本。
7. 历史不物理删除。错误记录标记失效并写入修正/替代记录。
8. 原始载荷与数据库备份的保留期限、归档层级和恢复目标在部署 ADR 中确定，但不得低于业务历史可重算要求。

## 7. 五类输出表的实现方式

- `Daily Ranking`：有效排名事实与当日 Listing/Offer 的逻辑视图。
- `New Product Entry`：读取 `detection_signal = NEW_PRODUCT`。
- `New Brand Tracker`：读取 `detection_signal = NEW_BRAND`。
- `Rising Products`：读取排名提升或 M&S 规则信号。
- `Trend Analysis`：读取 7/30/90 日产品与品牌聚合视图。

它们是视图/导出物，不是五份互相复制的事实数据，从而避免不一致。

## 8. 索引、分区与容量原则

- 历史大表优先按 `market_date` 分区；具体粒度由数据量压测决定。
- 高频索引覆盖 `(category_id, source_id, market_date, rank)`、`(product_id, market_date)`、`(brand_id, category_id, market_date)`。
- ASIN、内容指纹、运行状态和未解决质量问题建立约束或索引。
- 不在没有容量数据前承诺具体数据库产品或分区周期。

## 9. 数据质量规则

- ASIN 符合 10 位格式且 marketplace 内唯一映射。
- 排名为正整数，Best Sellers 目标范围原则上不超过 100，Search 不超过配置上限。
- Rating 位于 0–5；Review Count 非负；Price/Coupon 非负。
- `accepted_count / expected_count > 95%` 才达到完整率目标；expected 不可靠时同时报告页面覆盖率。
- 重复率按业务唯一键计算并要求小于 1%。
- 品类、来源、市场日期、ASIN、采集批次属于排名记录必需字段。

