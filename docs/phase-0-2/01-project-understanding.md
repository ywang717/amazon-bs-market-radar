# Phase 0 — 项目理解

## 1. 项目目标

建设可长期运行、可扩展的 Amazon 美国站家用设备市场情报平台，用于市场监控、新品和新品牌发现、增长识别、竞争分析及选品决策。系统不是一次性抓取工具，所有数据、规则和输出均应可追溯、可重算、可审计。

## 2. 首批市场范围

| 一级品类 | 监控入口 | 目标范围 |
|---|---|---|
| Pressure Washer | Best Sellers、Movers & Shakers、Search Results | Top 100、M&S 列表、指定搜索词 Top 50 |
| Sump Pump | Best Sellers、Movers & Shakers、Search Results | Top 100、M&S 列表、指定搜索词 Top 50 |
| Pressure Washer Accessories | Best Sellers、Movers & Shakers、Search Results | 按重点配件类型配置 |

配件类型：Spray Nozzle、Surface Cleaner、Foam Cannon、Pressure Washer Hose、Spray Gun / Wand、Adapter / Connector、Replacement Parts。

市场固定为 `Amazon.com / US`。系统同时保存 UTC 采集时间与美国太平洋时区市场日期，避免北京时间跨日造成趋势错位。

## 3. 核心业务问题

- 哪些 ASIN 今日首次进入目标榜单或搜索范围？
- 哪些品牌过去 30 天未出现、今日首次出现？
- 哪些产品排名快速提升，或在 Movers & Shakers 中出现强增长？
- 哪些高排名产品评论较少，可能存在低竞争窗口？
- 品牌、主机和配件之间有哪些布局、Bundle 和空白机会？
- Title、Bullet、Images 与评论体现了哪些需求、痛点和改进方向？

## 4. 业务定义

### 新产品进入

同一市场、规范品类和排名来源下，昨日无 Top 100 记录（等价于昨日排名大于 100 或未入榜），今日排名小于等于 100，标记 `NEW PRODUCT`。首次运行没有历史基线时，只标记 `BASELINE`，不误报新品。

### 新品牌

规范化品牌在同一市场及规范品类过去 30 个完整市场日内没有出现，今日出现，标记 `NEW BRAND`。品牌缺失或无法可靠规范化时不触发该信号。

### 上升产品

同一来源和品类下，`Previous Rank - Current Rank > 20`，或 Movers & Shakers 信号达到后续配置阈值。不同来源的排名不可直接相减。

### 趋势

按 7、30、90 个市场日窗口计算排名、价格、评分、评论数和品牌份额变化。窗口缺少足够历史时必须显示覆盖天数，不以零补齐。

### Opportunity Score

0–100 分，初始权重为：Rank Growth 30%、Review Velocity 20%、Rating 15%、New Product Signal 15%、Brand Growth 20%。分项先规范化到 0–100；最终阈值和缺失值策略在实现前用测试数据校准，版本化保存，不在本阶段武断固化。

## 5. 成功标准

- 产品记录必需字段完整率大于 95%。
- 同一业务唯一键下重复 ASIN 观测低于 1%，目标为 0%。
- 历史快照不可覆盖或删除；修正通过新版本或状态记录完成。
- 新品、新品牌和机会信号均可追溯到原始观测和规则版本。
- 新增品类只需增加品类、入口、关键词和映射配置，不修改核心处理链路。

## 6. 当前边界

本轮只交付设计文档和项目骨架。未选定采集技术与运行基础设施；未访问 Amazon；未生成真实数据；未实现数据库对象、数据模型或任何采集器。

