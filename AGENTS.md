# Project conversation instructions

- 对 Amazon BS 市场雷达进行增量工作时，只检查本次需求涉及的页面、数据、组件及其直接依赖；优先读取 Git diff 和最近修改内容。除非发现明确的跨模块问题，否则不要重新审查整个项目或扩大范围。

- When the conversation context usage reaches or exceeds 80%, compact the conversation context before processing the user's next instruction.
- Treat compaction as the first action for that next turn. Preserve the active task, completed work, unresolved decisions, relevant file paths, and verification results in the compacted context.
- If the client exposes `/compact`, invoke it. If direct slash-command invocation is unavailable, use the platform's automatic context-compaction mechanism before continuing.

## Low-token execution mode

- 优先复用已有上下文，以 Git diff 和本次需求为边界，只读取直接相关文件及必要依赖。
- 禁止无关全仓扫描、重复分析、重复测试和额外重构。
- 采用“最小修改 + 最小相关验证”；确认需求正确完成后立即停止。
- 只有发现明确的跨模块影响或正确性风险时，才扩大检查、修改或验证范围。
- 最终简洁汇报修改、验证结果和遗留问题。
