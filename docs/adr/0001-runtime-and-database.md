# ADR 0001：第二次运行的技术栈与数据库边界

- 状态：Accepted for development
- 日期：2026-08-03

## 决策

1. 生产逻辑数据库采用 PostgreSQL 兼容 DDL，利用约束、JSONB、时间戳和物化/普通视图表达已批准模型。
2. 当前本机没有 Python、Node、.NET SDK 或 PostgreSQL 客户端，因此采集核心先以 Windows PowerShell 5.1 的零依赖模块实现，并由现有 Pester 3.4 执行测试。
3. 采集器通过统一 Canonical Observation 契约与存储层隔离。本阶段写入追加式 JSONL staging；数据库连接器在获得 PostgreSQL 运行环境后实现。
4. 不发起真实 Amazon 请求。真实来源适配器必须等待准确类目节点、搜索词、地区上下文和获准数据渠道确定。

## 理由

- PostgreSQL 能可靠表达规范化关系、唯一约束、历史事实和 JSON 证据。
- 零依赖实现允许当前环境真正运行测试，而不是提交未验证代码。
- 契约和适配器边界使未来迁移到 Python 或托管任务运行时不改变数据库及下游分析接口。

## 后果

- 当前可验证 fixture 采集、字段规范化、拒绝原因和幂等暂存。
- 当前不能执行 PostgreSQL 集成测试或真实网络采集。
- 获得数据库和获准来源后，需要新增 Database Writer 与真实 Source Adapter，但无需重写领域契约。

