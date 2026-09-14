# V2.0 Final Optimization Screenshot QA

日期：2026-08-31  
检查环境：本地 Vinext 开发站点；D1 不可用时显示经过标识的 verified seed fallback。

## 覆盖范围

页面：总览、市场、产品、产品详情、品牌、榜单、报告、数据状态。  
桌面视口：1366×768、1440×900、1920×1080。  
移动保护视口：390×844。

共生成 32 张截图，位于 `docs/screenshots/v2-final/`。

## 自动检查结果

- 24/24 桌面页面无 document-level 横向溢出。
- 8/8 移动页面无 document-level 横向溢出；表格继续在局部容器内滚动。
- 32/32 页面未出现 Internal Server Error / Application Error。
- 1366×768 首页首屏包含导航、市场上下文、摘要、四个 KPI 和完整的第一条信号/空状态。
- 1440×900 市场页完整展示状态头、多视图 tabs、1D/3D/7D/30D 与概览指标。
- 榜单保留原始 Amazon Top30，产品身份、排名和变化保持可纵向扫描。

## 视觉复核

- 信息层级：Signal → Market State → Raw Data → Technical Information 成立。
- Raw/Analytical 标签：榜单明确标注“Amazon 原始榜单”；其他核心页明确“整机分析市场”。
- Data Status 与 Methodology 保持低权重入口，没有重新占据首页。
- High/Watch 与普通 Activity 在首页和市场页分离。
- Brand 使用整机分母，并明确 Seat Share 不是销量或市场份额。
- Dark Theme、边框、圆角、数字等宽与原有 V2 设计系统一致，没有新增大面积渐变、霓虹或复杂动画。

## 环境说明

本地站点无法连接线上 D1 时，页面按既有安全策略显示“实时数据暂不可用 / 已验证回退数据”；因此本地截图中的整机样本可能为空。Machines 过滤的有数据行为由 Node 集成测试和线上部署后烟雾测试验证，未使用假数据绕过该状态。
