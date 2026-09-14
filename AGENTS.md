# Project conversation instructions

本文件位于仓库根目录，作为整个项目的默认 Codex 长期执行规则。更具体目录中的 `AGENTS.md` 或 `AGENTS.override.md` 可以按 Codex 规则覆盖本文件；当前仓库未发现其他项目级指令文件。

# Codex 项目自主执行规则

## 核心执行原则

对于本项目中的所有 Codex 任务，默认采用：

**理解任务 → 自行规划 → 直接执行 → 遇错自行修复 → 完整验证 → 提交结果 → 最后统一汇报**

除非遇到真正无法自行解决的阻塞，否则不要在任务执行过程中停下来要求用户确认。

## 默认无需确认的操作

以下操作在当前仓库和当前任务范围内默认直接执行：

- 阅读项目文件、搜索代码、分析项目结构
- 修改已有代码、创建项目所需文件、重构代码、修改配置文件
- 删除由本次任务产生且确认无用的项目文件
- 安装完成任务所必需的依赖、执行终端命令、启动开发环境、执行脚本
- 执行 build、lint、test、typecheck 及必要的运行验证
- 修复测试失败、构建错误和依赖问题
- 查看 git status、diff、log，执行 git add 和 git commit

不要为了上述普通开发步骤暂停任务询问用户。

## 自主决策

当存在多个合理实现方案时，选择最符合用户最终需求、风险最低、改动范围最小、与当前架构一致且易于维护的方案；优先复用已有代码，不破坏已有功能，不增加无必要依赖，不做无必要的大规模重构。

## 遇到错误时

遇到报错、测试失败、构建失败或代码问题时，先阅读错误信息，定位相关代码并分析根因，随后实施修复、重新运行和验证。第一次方案失败时继续尝试其他合理方案，不因普通技术问题暂停等待用户确认。

## 完成任务的标准

不得仅修改代码后宣布完成。修改完成后，根据项目实际情况主动执行适用的 build、test、lint、typecheck、必要的运行验证以及页面、接口或功能验证；发现问题继续修复，只有合理验证通过后才认为任务完成。

## Git 行为

完成任务并验证通过后，检查 git diff，确认没有误修改无关文件，执行 git add 并创建清晰准确的 commit。如果当前环境与权限允许，且任务明确涉及远程仓库更新，则直接 push 当前工作分支。不得覆盖用户已有且与当前任务无关的修改。

## 控制任务范围

发现与当前任务无关的历史错误时：如果不会影响本次任务则记录但不扩大范围；如果会阻塞本次任务则进行最小必要修复；不要因为顺手优化而进行大规模无关重构。对 Amazon BS 市场雷达进行增量工作时，只检查本次需求涉及的页面、数据、组件及其直接依赖；优先读取 Git diff 和最近修改内容。除非发现明确的跨模块问题，否则不要重新审查整个项目或扩大范围。

## 仅允许暂停询问用户的情况

只有出现以下情况之一，才允许中断执行询问用户：

1. 需要用户提供密码、验证码、API Key、Secret 或其他不存在的凭证；
2. 必须由用户亲自完成第三方登录或授权；
3. 即将执行明显不可逆的高风险操作，例如删除生产数据库、清空生产数据、删除大量真实用户数据或删除关键生产资源；
4. 用户需求之间存在关键性冲突，并且无法根据项目上下文合理判断；
5. 当前环境或权限从技术上完全阻止任务继续。

普通代码实现选择、文件修改、依赖安装、测试失败和构建错误不属于需要询问用户的情况。

## 禁止行为

不要每完成一步就询问用户是否继续；不要只给方案或 PRD 而不执行；不要修改一个文件后就停止；不要测试失败后立即把问题抛给用户；不要因为有多个实现方案就要求用户选择；不要因为任务较大就主动缩减用户需求；不要反复询问已经能够从项目上下文判断的问题。

## 最终汇报

任务完成后统一汇报：完成了什么、修改了哪些关键文件、关键实现方式、build/test/lint/typecheck 状态、Git commit ID、是否已经 push，以及剩余问题或风险。没有剩余问题时明确说明任务已经完成。

## 优先级

本 `AGENTS.md` 是本项目的默认长期执行规则。之后用户在具体任务中提出的明确要求优先于这里的通用规则；如果用户没有额外说明，则始终按本文件的自主执行规则工作。

- When the conversation context usage reaches or exceeds 80%, compact the conversation context before processing the user's next instruction.
- Treat compaction as the first action for that next turn. Preserve the active task, completed work, unresolved decisions, relevant file paths, and verification results in the compacted context.
- If the client exposes `/compact`, invoke it. If direct slash-command invocation is unavailable, use the platform's automatic context-compaction mechanism before continuing.

## Low-token execution mode

- 优先复用已有上下文，以 Git diff 和本次需求为边界，只读取直接相关文件及必要依赖。
- 禁止无关全仓扫描、重复分析、重复测试和额外重构。
- 采用“最小修改 + 最小相关验证”；确认需求正确完成后立即停止。
- 只有发现明确的跨模块影响或正确性风险时，才扩大检查、修改或验证范围。
- 最终简洁汇报修改、验证结果和遗留问题。
