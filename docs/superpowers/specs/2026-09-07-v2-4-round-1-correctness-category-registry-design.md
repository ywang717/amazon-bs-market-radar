# Amazon BS 市场雷达 V2.4 第一轮设计规范

**主题：数据正确性与可扩展 Category Registry**

**日期：2026-09-07**

**状态：设计已逐节确认，等待书面规范复核**

## 1. 目标与范围

本轮仅实施 V2.4 PRD 的第一轮能力：

1. Stage 1 — Correctness Audit
2. Stage 2 — Correctness Fix
3. Stage 3 — Category Registry + Schema
4. 相关单元测试、集成测试、类型检查、构建与关键页面回归

核心目标是先修正现有产品详情、优惠、Review Event、时间窗口和产品规格语义，再建立单一权威 Category Registry，使新增榜单不再要求在抓取、分析、报告和前端中分别维护重复的 Category 定义。

本轮不实现 Seller Decision Layer、Opportunity Finder、Product Lifecycle、Review Velocity、销售或收入估算、Forecast、Watchlist、AI Assistant、账号系统或新 Marketplace。完成本轮验收后必须停止，等待用户明确启动下一阶段。

## 2. 已确认的现状

### 2.1 当前三个生产市场

| Category Key | 中文名称 | Amazon Node | 状态 |
| --- | --- | ---: | --- |
| `pressure_washers` | 高压清洗机 | `552856` | 保持兼容 |
| `sump_pumps` | 污水泵 | `680335011` | 名称、Key 和 Node 保持不变 |
| `pressure_washer_accessories` | 高压清洗机配件 | `3023451` | 保持为独立 Amazon 榜单 |

高压清洗机原始榜单中的配件与独立高压清洗机配件榜单必须继续严格区分，不能互相冒充数据源。

### 2.2 已确认的正确性问题

- 产品详情页没有向共享 `ProductIdentity` 传递与 Products、Rankings 相同的品牌和 Product Type metadata，导致已分类产品可能显示为 Unknown。
- 优惠验证把优惠金额大于当前售价视为无效，但 Amazon 的合法优惠证据可能满足该条件；列表与详情还使用了不同的优惠格式化路径。
- Review Momentum 使用紧凑数字格式，无法准确表达事件前值、后值和增量；产品时间线缺少 Review Change Event。
- Overview 使用前一个有效市场日进行比较，但时间窗口标签不够明确。
- 产品规格标签主要按 Category 解释，没有同时依据 Product Type，可能错误套用 PSI 等字段语义。
- 品牌分析的总体口径基本正确，但部分文案仍使用“市场席位”，应统一为“榜单席位”，避免被理解为销售市场份额。

### 2.3 当前配置分散

Category、Node、Segment、默认值和分类规则目前分散在 JSON、PowerShell、TypeScript、脚本参数、报告与测试中。现有 D1/数据库使用字符串 `category_key`，因此建立 Registry 不要求数据库 Schema 迁移。

## 3. 方案选择

采用“权威 JSON Registry + PowerShell 适配器 + 生成的类型安全 Web Registry”。

```text
config/category-registry.json
        │
        ├── Collection / Snapshot / Operational Health
        ├── Classification / Analysis / Reports
        └── Generated Web Registry
                ├── Category / Segment Selector
                ├── Market Context
                ├── Universe Filtering
                └── Product Attribute Rendering
```

不采用运行时数据库 Registry，因为它会引入本轮不需要的 Schema、部署与启动依赖。不采用长期保留多份平行配置并仅做同步检查，因为它不能真正建立单一事实来源。

## 4. 权威 Category Registry

### 4.1 Registry 职责

`config/category-registry.json` 是生产 Category 定义的唯一权威来源。每个条目至少定义：

- 稳定的 `categoryKey`
- 中文与英文显示名称
- Marketplace
- Amazon Node 与来源 URL
- 预期榜单容量
- 启用状态
- 支持的 Segment
- 各页面默认 Segment
- Product Classification Rules 引用
- Product Attribute Schema 引用

Registry 管理 Category 能力及其引用，不复制分类关键词或页面实现逻辑。具体分类规则和属性 Schema 可以保留在独立配置中，但必须由 Registry 显式引用，且引用在启动、测试和构建时受到验证。

### 4.2 适配器边界

- PowerShell 适配器负责加载、验证、枚举 Category，并为抓取、健康检查、分析和报告提供稳定接口。
- Web 端消费由 Registry 生成的类型安全模块，不在页面内维护手写 Category 联合类型或平行数组。
- 生成过程必须可重复；源 Registry 与生成产物不一致时，测试或 Production Build 失败。
- 页面选择器、Market Context、Segment Resolver 和属性展示均通过共享 Registry 接口读取配置。

### 4.3 数据兼容性

- 数据库继续存储字符串 `category_key`，本轮不做数据库迁移。
- 历史 Raw Snapshot 保持只读，不重写、不回填、不重新解释。
- 现有 Snapshot 的 Category 属性结构保持兼容；新增 Category 只增加新的合法 Key。
- 旧数据缺少新增字段时采用兼容读取，不构造虚假值。
- 测试 Category 只通过临时 Fixture Registry 注入，不进入生产配置或生产导航。

## 5. 正确性修复设计

### 5.1 统一数据流

```text
Raw Snapshot
    ↓
Valid Market Day 筛选
    ↓
Canonical Product Metadata
    ↓
Product Classification
    ↓
Market Universe
    ↓
Analysis / Signals / Brands / Reports
    ↓
Shared Formatting
    ↓
业务页面
```

所有分析页面必须消费相同的 canonical metadata 和 Market Universe。页面不得重新实现分类或自行构建另一套 Product Universe。

### 5.2 Product Identity

- 产品详情页从与 Products、Rankings 相同的 metadata 源取得品牌、Product Type、短名称与图片。
- `ProductIdentity` 的调用方必须传递已解析 metadata，或组件通过唯一共享接口获得 metadata。
- 只有权威 metadata 确实缺少分类时才显示 Unknown。
- 完整 Amazon Title 继续用于 Tooltip 或详情，不在紧凑表格中替代 Display Name。

### 5.3 Discount / Deal

- 优惠语义至少区分类型、金额、来源和验证状态。
- 优惠金额大于当前售价本身不是无效证据，不能因此自动丢弃。
- 验证失败必须基于缺失、类型错误、负值、不可信来源或明确的证据冲突。
- Rankings、Products 和 Product Detail 使用同一格式化与验证入口。
- 无优惠显示 `—`；已验证金额显示 `$30 OFF`；证据不足时显示明确的待确认状态。
- 历史原始优惠字段保持不变，只修 canonical validation 和 display 层。

### 5.4 Review Change Event

- KPI 和列表继续使用 `8.9K` 等紧凑格式。
- 事件展示使用独立的精确格式，例如 `8,949 → 8,977  +28`。
- Product Timeline 增加 Review Change Event，并保持与 Rank、Price、Coupon 等事件相同的时间排序规则。
- Missing 与真实零值严格区分。

### 5.5 时间窗口

- 所有变化指标显式标注 `1D`、`7D` 或 `30D`。
- Overview 的当前市场日对 Previous Valid Market Day 比较明确标注为 `1D`。
- “上一日”表示 Previous Valid Market Day，而不是自然日。
- 不完整抓取日和失败抓取不得参与 Exit、Turnover、Rank Trend 或 Brand Contraction。

### 5.6 Product Specifications

- 属性 Schema 同时依据 Category 和 Product Type 选择标签、单位及是否适用。
- PSI 在高压清洗机整机中表达工作压力；在不适用的水泵或配件类型中不得套用相同语义。
- 不适用字段省略；存在字段但值缺失时显示 `—`；不能用其他 Category 的字段补齐。

### 5.7 分析与文案一致性

- 同一个 `category + segment + date` 在 Overview、Market、Products、Brands、Signals 和 Reports 中产生相同 Product Universe。
- Rankings Raw 模式继续忠实保留 Amazon 原始榜单，不受 Analytical Segment 过滤。
- Brand Seat Count、Seat Share 和 Top3 Concentration 使用同一分析分母。
- 全站使用“榜单席位”“榜单席位占比”，明确不代表销售市场份额。

## 6. 迁移策略

实施顺序固定为：

```text
Correctness Audit
    ↓
正确性回归测试与修复
    ↓
Registry Schema 与校验器
    ↓
三个现有市场配置迁入
    ↓
PowerShell 读取适配器
    ↓
类型安全 Web Registry 生成
    ↓
Classification / Market Universe 接入
    ↓
抓取、Health、Analysis、Reports 接入
    ↓
页面与共享展示接入
    ↓
删除已证明无调用方的重复 Category 定义
```

每一步都必须保持三个现有生产市场可用，并在相关测试通过后进入下一步。旧配置只在所有调用方迁移并有测试证明后删除，不能先删再补。

## 7. 校验与失败处理

Registry 校验必须拒绝：

- 重复 `categoryKey`
- 重复 Amazon Node
- 非法 Marketplace
- 缺失来源 URL 或预期榜单容量
- 没有可用 Segment
- 默认 Segment 不属于支持列表
- 缺失或无效的分类规则引用
- 缺失或无效的属性 Schema 引用
- Category 与 Segment classification filter 不一致
- 启用 Category 缺少抓取所需配置

失败策略：

- 未知或禁用 Category 必须 fail closed，不能默认为高压清洗机。
- 无效 URL Segment 可由共享 Resolver 规范为该页面、该 Category 的默认 Segment；后端不能静默接受无效 Segment。
- 配置或生成产物无效时在测试、构建或任务启动前失败，不允许部分写入数据。
- Product Classification 证据不足时返回 `unknown`，不强制进入 Machines 或 Accessories Other。
- 历史 Snapshot 不因 Registry 校验失败而被修改或删除。

## 8. 测试设计

### 8.1 Correctness 单元测试

- 产品详情与列表使用相同品牌、Product Type 和 metadata。
- 合法优惠金额高于当前售价时仍可通过验证。
- Rankings、Products、Detail 的 Deal 展示一致。
- Review Event 使用带千位分隔符的精确前值、后值和增量。
- Timeline 事件排序正确。
- 1D、7D、30D 标签与实际比较窗口一致。
- Product Spec 标签按 Category + Product Type 选择。
- `unknown` 不进入 Machines 或配件 Other。

### 8.2 Registry 合同测试

- 三个现有 Category 完整加载。
- `sump_pumps` 保持 Node `680335011`。
- 重复 Key、重复 Node、无效默认 Segment、无效 Schema 引用均失败。
- PowerShell 和 Web 对相同 Registry Fixture 得到等价 Category 与 Segment 集合。
- 生成 TypeScript Registry 与源 JSON 一致。
- 修改源 Registry 而不更新生成产物时测试或 Build 失败。

### 8.3 Test Category 集成测试

测试通过临时 Registry Fixture 注入第四个 Category，覆盖：

```text
Registry → Snapshot → Classification → Market Universe
         → API → Market Context → Reports → Health
```

验收要求：

- 不修改生产 Registry。
- 不写入真实历史 Snapshot。
- 不污染三个生产市场的缓存。
- 测试结束后不留下导航入口或构建产物。
- 新 Category 不需要修改 Overview、Market、Products、Brands、Rankings 或 Reports 的页面级 Category 分支。

### 8.4 分析一致性测试

- 相同 Context 下各分析页面的 ASIN 集合相同。
- Brands 的 Seat Count、Seat Share 和分母与 Market 一致。
- Raw Rankings 不被 Analytical filter 删除。
- Incomplete/Failed crawl 不产生 Exit、Turnover 或 Brand Contraction。
- Cache Key 包含 `marketplace + category + segment + date/window`。

### 8.5 验证命令类别

具体命令由实施计划根据仓库现有脚本确定，至少包括：

- 相关 PowerShell/Pester 测试
- Web Node 测试
- TypeScript 类型检查
- Lint
- Production Build
- `git diff --check`
- 关键页面浏览器回归

关键页面至少检查 Overview、Market、Products、Product Detail、Brands、Rankings、Reports 和 Data Status，并覆盖三个现有市场、URL Context、页面刷新、格式一致性和历史数据读取。

## 9. 安全与回滚

- 不修改历史 Raw Snapshot。
- 不进行不可逆数据库 Schema 变更。
- 不通过重新抓取掩盖历史正确性问题。
- 每个迁移步骤形成独立、可验证的提交。
- 发生兼容问题时回退对应适配器或调用方，不重置、删除或重写用户现有数据。
- 当前工作区已有的未提交修改属于前序任务，本轮实施与提交必须精确选择文件，避免覆盖或混入无关改动。

## 10. 第一轮完成条件

以下条件必须同时满足：

1. Correctness Audit 已保存，且每个发现标记为已修复、保留或超出范围。
2. 本规范列出的产品详情、优惠、Review Event、时间窗口、产品规格和语义问题已修复。
3. Category Registry 成为生产 Category 的唯一权威来源。
4. 三个现有 Category 的抓取、分析、报告和页面行为保持兼容。
5. Test Category 证明新增榜单不需要跨业务页面维护重复 Category 分支。
6. 相关测试、类型检查、Lint 与 Production Build 通过。
7. 浏览器回归未发现跨 Category 数据污染或主要页面退化。
8. 没有修改历史 Snapshot，也没有提前实现第二轮卖家决策功能。

若 Production Build 或必要测试因环境因素无法运行，结果必须明确记录为未验证或失败，不能声称 PASS。

## 11. 强制停止边界

第一轮验收完成后立即停止。以下能力只能记录为后续候选，不得在本轮实现：

- Seller Decision Layer
- Opportunity Finder
- Product Lifecycle
- Review Velocity
- Sales / Revenue Estimate
- Forecast
- Watchlist
- AI Assistant
- User Accounts
- New Marketplace

下一阶段必须由用户明确启动，并单独完成设计、计划与验收。
