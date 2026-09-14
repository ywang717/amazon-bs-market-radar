# Amazon BS Market Radar V2.0 Visual UI/UX Design

## Background and Objective

现有网站业务能力和数据边界稳定，但视觉层级由数据质量和方法说明主导。V2 在不改技术栈、数据口径、API 安全边界和历史数据的前提下，将体验升级为以市场信号为中心的暗色 Market Intelligence SaaS。

核心顺序：`Signal → Market State → Raw Data → Technical Information`。

## Scope

- 暗色 Design Token、排版、间距、Surface、语义颜色、焦点和数字格式。
- 共享 MarketContext、MetricCard、SignalCard、Rank、ProductIdentity、Badge、Drawer、Empty/Loading/Error、Timeline。
- 六项一级导航、Alerts、Data Status、Methodology 和可用移动导航。
- 重构总览、榜单、产品列表、产品详情、洞察、报告。
- 新增只读 `/market` 与 `/brands` 页面，复用现有 dashboard 与 product metadata。
- 保留 `/analysis` 卖家情报和智能报告能力，视觉统一但不改报告合同。

## Out of Scope

- 不修改爬虫、PostgreSQL/D1 schema、历史数据、排名/证据/覆盖率计算口径。
- 不新增大型 UI 或图表框架，不新增复杂动画。
- 不推断商品图片、价格事件、评论动量、销量或市场份额。
- 不创建无算法定义的综合 Market Score。

## Architecture

### UI Intelligence Layer

新增 `web/lib/ui-intelligence.ts`，只接受现有 `DashboardView` 与 `ProductMetadata`，输出可渲染的 View Model：

- `buildMarketSignals`：过滤现有 comparison mover、Top30 entry/exit 与已验证优惠事实；High 为绝对排名变化 ≥20，Watch 为 10–19，Entry 使用当前/上一有效市场日集合差。
- `buildMarketState`：Top10 stability 使用现有 `top10Retained / 10`；volatility 由现有 `averageAbsoluteMove` 映射 Low/Medium/High；turnover 使用现有 entries + exits 映射 Low/Medium/High。阈值写入 Tooltip/Methodology。
- `buildBrandMovement`：在所选分析分群内，将当前和上一有效市场日的已验证品牌按 ASIN 计席位差；未知品牌归入 Unknown，但首页 Top Movement 不突出 Unknown。
- `buildProductRows`：把 Observation、已有 raw rank comparison 与 ProductMetadata 组合，绝不改变原始 Rank。

### Data Boundary

`loadVerifiedDashboardFromStore` 在原有三项只读查询旁加载 Product Metadata，并把它附加到 `DashboardView.productMetadata`。Seed fallback 使用空 metadata，不猜测品牌或产品类型。公开 API 现有字段和写入路径不变。

### Component Boundary

- 纯展示组件从 View Model 接收数据，不自行访问 D1。
- Drawers 是客户端组件，只通过现有公开只读 API 获取状态；失败时显示可恢复 Error State。
- 页面继续服务端加载，保持当前动态渲染和公开数据保护。

## Information Architecture

- 一级：总览 `/`、市场 `/market`、产品 `/products`、品牌 `/brands`、榜单 `/rankings`、报告 `/analysis`。
- 报告页内保留智能报告、卖家预警、竞争策略和 PDF 报告入口。
- `/insights` 保留并改为市场洞察视图；`/reports`、`/methodology` 保留直接访问。
- 右侧：Alerts Drawer、Data Status Drawer、Methodology 链接。

## Page Designs

### Overview

紧凑 MarketContext + 日期、市场标题和一句自动摘要；四个 KPI；最多五个 Signal；Brand Movement 与 Market Structure 并排。数据质量 Timeline、Evidence Ladder 和 Coverage 不出现在首页主体。

### Rankings

保留类别 Tab、搜索和 Top 范围；表格改为 Product / Rank / 7D / Price / Rating / Reviews / Deal。ProductIdentity 合并 ASIN 与 Product Type，完整标题通过 `title` 和详情页查看；表头 Sticky，数字右对齐。

### Products and Product Detail

产品页展示当前类别全部产品，支持关键词、All/Rising/Top10/New/Falling。详情页顶部合并身份与当前状态；Rank Timeline 反向 Y 轴并轻标 Top10；事件只从已有历史价格、优惠、Top10/Top30 边界变化生成。

### Market and Brands

Market 显示 Stable/Moderate/Volatile、Top10 Stability、Turnover 和可验证品牌集中度。Brand 页面先展示 Presence bars，再展示品牌表和 Seat Movement；不把 Seat Share 表述为销量份额。

### Insights, Analysis and Reports

Insights 主体展示真实信号与市场状态；Data Readiness 链接到 Data Status/Methodology。Analysis 与 Reports 保留全部旧能力，只替换标题、卡片、Badge、表格和状态组件。

## States and Accessibility

- Loading：Skeleton，保留 `aria-busy` 和可读状态文本。
- Empty：说明当前没有高优先级异常，并提供 Market 链接。
- Error：明确“读取失败”，不与无数据混淆，提供重试或目标链接。
- Incomplete：明确当前市场日或比较日不完整，隐藏比较结论。
- 主导航和 Drawer 全键盘可操作；Escape 关闭 Drawer；Icon Button 有可访问名称；全局 `:focus-visible`；颜色之外同时显示箭头和文字 Badge。

## Responsive Acceptance

- 1366×768 首屏看到 Navigation、MarketContext、Summary、4 KPI 和第一条完整 Signal。
- 1440×900、1920×1080 无无限拉伸，内容最大宽度 1520px。
- 650px 下导航可打开，Drawer 不超屏，卡片堆叠，表格横向滚动，页面本身无严重横向溢出。

## Testing and Definition of Done

- UI Intelligence 纯函数单元测试覆盖 High/Watch/Entry、不可比较、品牌 Seat Movement、格式化和 Unknown。
- 构建后路由测试验证六项导航、MarketContext、Data Status/Alerts、首页层级、榜单 ProductIdentity、新页面和旧路由可达。
- 完整 Web test/build/lint 通过；三种桌面尺寸和移动宽度完成 Screenshot/Overflow/First-screen QA。
- 不修改 D1 schema、sync contract、crawler 或历史数据；无 P0/P1 回归。
