# 本地单机德州扑克 V1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在独立的 `poker-game/` 包中交付一款完全离线、中文、单人对 AI 的标准/短牌德州扑克生涯游戏。

**Architecture:** 采用纯 TypeScript 领域核心与 React/Vite 展示层分离。`GameEngine` 只接收显式命令并返回可序列化状态，AI 只消费公开桌面状态和自己的底牌，Zustand 负责 UI 订阅，IndexedDB 负责生涯和断点快照。先审计 `@hivetech/poker-engine`；若其确定性牌堆、浏览器打包、边池和快照接口全部满足验收，则通过内部 `PokerCoreAdapter` 复用标准下注核心，否则使用同一接口的本地实现。

**Tech Stack:** React 19、TypeScript、Vite、Zustand、原生 IndexedDB、Vitest、`fake-indexeddb`（测试依赖）、普通 CSS。

**Spec:** `docs/superpowers/specs/2026-09-29-local-poker-game-v1-design.md`

## Global Constraints

- 完全离线运行，无服务器、登录、联网匹配、真钱、充值和广告。
- 规则逻辑、AI、Career System、Save System 与 React UI 分离。
- 标准模式使用 52 张牌；短牌模式使用 6-A 的 36 张牌，A6789 为顺子，同花大于葫芦。
- 支持 2、3、4、5、6、8、9 人桌；Heads-Up 时 Dealer 同时为 SB，翻牌前 Dealer 先行动，翻牌后 BB 先行动。
- 使用 Fisher-Yates 或等价无偏洗牌；洗牌后立即保存完整牌堆，恢复不得重新洗牌。
- 所有筹码为非负整数；主池、任意多层边池、弃牌资格、All-in 和 Split Pot 必须守恒且幂等。
- 本地历史最多保存最近 500 手；损坏存档先尝试最近有效备份，再显示可恢复错误。
- UI 为中文白色极简风，最低桌面尺寸 1280×720；禁止绿色赌场主题、联网功能和无关玩法。
- 每个功能按 TDD：先写失败测试并确认失败，再实现最小代码，最后运行完整测试套件。

## Review Focus

1. 多层边池中不同筹码量、弃牌玩家和 Split Pot 的资格与余数不能导致重复派奖或筹码丢失；由 Task 4 的 `multiLayerSidePotSettlement` 测试覆盖。
2. 强制关闭发生在任意街道或 All-in 后必须恢复同一牌堆、底牌、公共牌、行动顺序和底池；由 Task 7 的 `restoresHandWithoutRedealing` 测试覆盖。
3. 短牌的 A6789 和“同花大于葫芦”不能被标准牌型排序覆盖；由 Task 2 的短牌评估测试覆盖。
4. Heads-Up 与 3/4/5/6/8/9 人桌的盲注和行动顺序必须一致且无死循环；由 Task 3 的桌型参数化测试覆盖。
5. AI 输入不能包含真人或其他 AI 未公开底牌、未来公共牌或牌堆顺序；由 Task 5 的 `aiContextContainsOnlyVisibleInformation` 测试覆盖。

## File Map

所有产品文件位于 `poker-game/`，现有 Amazon 项目 `web/` 不修改。核心测试与实现同目录按领域分组；页面不直接导入底层 IndexedDB 或牌型比较函数。

### Task 1: Scaffold and engine audit

**Files:**
- Create: `poker-game/package.json`, `poker-game/tsconfig.json`, `poker-game/vite.config.ts`, `poker-game/index.html`
- Create: `poker-game/src/test/setup.ts`, `poker-game/tests/compat/poker-engine-compatibility.test.ts`
- Create: `poker-game/docs/ENGINE-AUDIT.md`

**Interfaces:**
- Produces: package scripts `dev`, `build`, `test`, `typecheck`; audit result defining whether `PokerCoreAdapter` may wrap `@hivetech/poker-engine`.

- [ ] **Step 1: Write the failing compatibility tests**

  Add tests for: deterministic `start-hand` with a complete 52-card deck; JSON serialize/restore equality; legal action range; Heads-Up order; 9-seat table; unequal All-in side pots; odd-chip split. Import `@hivetech/poker-engine` directly in this audit-only test so a missing package or API mismatch fails clearly before the product adapter exists.

- [ ] **Step 2: Run the audit tests and confirm the expected failure**

  Run `npm test -- --run tests/compat/poker-engine-compatibility.test.ts` from `poker-game/`. Expected failure is missing package/API mismatch, not a test syntax error.

- [ ] **Step 3: Implement the Vite/TypeScript scaffold and install pinned dependencies**

  Add React, React DOM and Zustand as runtime dependencies; add Vite, TypeScript, Vitest, fake-indexeddb and React type packages as development dependencies. Use Node `>=22.13.0`, ESM, and `vitest run` as the test command. Install `@hivetech/poker-engine@1.0.1` only for the audit.

- [ ] **Step 4: Run the audit and record the decision**

  Run `npm install` then the compatibility test. Record pass/fail for every criterion in `poker-game/docs/ENGINE-AUDIT.md`. If any criterion fails, mark the candidate reference-only and implement the adapter locally in later tasks; do not weaken the PRD to fit the package.

- [ ] **Step 5: Verify scaffold and commit**

  Run `npm run typecheck` and `npm run build`; expected exit code 0. Commit `chore: scaffold poker game package and audit engine`.

### Task 2: Cards, rule configuration, and hand evaluator

**Files:**
- Create: `poker-game/src/game/cards.ts`, `poker-game/src/game/rules.ts`, `poker-game/src/game/handEvaluator.ts`
- Create: `poker-game/tests/game/cards.test.ts`, `poker-game/tests/game/handEvaluator.test.ts`

**Interfaces:**
- Consumes: Task 1 TypeScript/Vitest setup.
- Produces: `createDeck(mode): Card[]`, `shuffleDeck(deck, rng): Card[]`, `evaluateHand(holeCards, board, mode): HandEvaluation`, `compareEvaluations(a, b): number`, `getRuleConfig(mode): RuleConfig`.

- [ ] **Step 1: Write failing card and evaluator tests**

  Cover 52-card uniqueness, 36-card removal of 2/3/4/5, deterministic Fisher-Yates with an injected RNG, all ten standard categories, wheel straight, kicker comparison, board-only best five, A6789 short-deck straight, and short-deck flush beating full house.

- [ ] **Step 2: Run `npm test -- --run tests/game/cards.test.ts tests/game/handEvaluator.test.ts` and confirm failure**

- [ ] **Step 3: Implement card and rule types plus a shared five-card evaluator**

  Use one evaluator pipeline with `RuleConfig` for rank set, straight windows, and category ordering; enumerate all five-card combinations from up to seven cards and return category, Chinese/English labels, best five cards, and rank vector.

- [ ] **Step 4: Run the focused tests, then the full suite**

  Expected focused and full Vitest runs pass with no warnings.

- [ ] **Step 5: Commit**

  Commit `feat: add standard and short deck hand evaluation`.

### Task 3: Betting state machine, dealer order, and engine adapter

**Files:**
- Create: `poker-game/src/game/gameState.ts`, `poker-game/src/game/betting.ts`, `poker-game/src/game/dealer.ts`, `poker-game/src/game/gameEngine.ts`, `poker-game/src/game/coreAdapter.ts`
- Create: `poker-game/tests/game/betting.test.ts`, `poker-game/tests/game/gameEngine.test.ts`, `poker-game/tests/game/dealer.test.ts`

**Interfaces:**
- Consumes: Task 2 `Card`, `GameMode`, `RuleConfig`, `evaluateHand`.
- Produces: `createTable(config): GameState`, `startHand(state, deck): GameState`, `getLegalActions(state, playerId): LegalActionSet`, `applyAction(state, action): TransitionResult`, `advanceStreet(state): GameState`, `getActionOrder(tableSize, dealerSeat, street): number[]`.

- [ ] **Step 1: Write failing tests**

  Test check/call/bet/raise/fold/all-in validation, min raise and max stack, street transitions, dealer rotation, all seven supported table sizes, Heads-Up blind/action order, and rejection of actions out of turn or with negative/under-raise amounts.

- [ ] **Step 2: Run the focused tests and confirm failure**

  Run `npm test -- --run tests/game/betting.test.ts tests/game/gameEngine.test.ts tests/game/dealer.test.ts`.

- [ ] **Step 3: Implement immutable state transitions**

  `GameState` must hold players, deck and deck index, dealer/SB/BB, street, acting seat, board, per-street and total contributions, folded/all-in flags and action history. `coreAdapter.ts` wraps the audited package only when Task 1 passed; otherwise it exposes the local transition implementation with the same signatures.

- [ ] **Step 4: Verify focused and full tests**

  Run the three focused files and `npm test`; expected all pass.

- [ ] **Step 5: Commit**

  Commit `feat: add deterministic betting state machine`.

### Task 4: Pots, All-in settlement, and chip conservation

**Files:**
- Create: `poker-game/src/game/pot.ts`, `poker-game/src/game/sidePot.ts`, `poker-game/src/game/settlement.ts`
- Create: `poker-game/tests/game/sidePot.test.ts`, `poker-game/tests/game/settlement.test.ts`

**Interfaces:**
- Consumes: Task 2 `HandEvaluation`, Task 3 player contributions and dealer seat.
- Produces: `buildPots(players): Pot[]`, `settlePots(pots, eligiblePlayers, evaluations, dealerSeat): SettlementResult`, `assertChipConservation(before, after): void`.

- [ ] **Step 1: Write failing settlement tests**

  Pin two-player All-in; three players with 1,000/5,000/10,000; four players with multiple layers; folded contributors; different winner per pot; exact ties; odd-chip remainder from Dealer-left order; repeated settlement returning the same result.

- [ ] **Step 2: Run focused tests and confirm failure**

  Run `npm test -- --run tests/game/sidePot.test.ts tests/game/settlement.test.ts`.

- [ ] **Step 3: Implement contribution-layer pot construction and independent payouts**

  Build layers from sorted positive contributions, exclude folded players from eligibility but retain their chips in amounts, evaluate each layer independently, and allocate integer remainders clockwise from the first eligible seat left of the button.

- [ ] **Step 4: Verify focused, full, and property-style randomized tests**

  Add a deterministic seeded simulation of at least 500 random contribution layouts and assert total chips before equals total chips after. Run `npm test`.

- [ ] **Step 5: Commit**

  Commit `feat: implement side pots and split pot settlement`.

### Task 5: AI context, five difficulty levels, and personalities

**Files:**
- Create: `poker-game/src/ai/publicContext.ts`, `poker-game/src/ai/difficulty.ts`, `poker-game/src/ai/preflopRanges.ts`, `poker-game/src/ai/postflop.ts`, `poker-game/src/ai/playerModel.ts`, `poker-game/src/ai/aiEngine.ts`, `poker-game/src/ai/personalities.ts`
- Create: `poker-game/tests/ai/aiEngine.test.ts`, `poker-game/tests/ai/informationBoundary.test.ts`

**Interfaces:**
- Consumes: Task 3 `GameState`/`LegalActionSet`, Task 2 evaluator, Task 4 pot amounts.
- Produces: `toPublicContext(state, aiSeat): PublicTableContext`, `chooseAction(context, difficulty, personality, rng): PlayerAction`, `recordObservedAction(model, record): PlayerModel`.

- [ ] **Step 1: Write failing AI tests**

  Assert context omits all hidden cards, future deck entries and final results; heads-up ranges are wider than 8/9-handed early-position ranges; short-deck preflop uses separate parameters; each level selects within legal actions; personality shifts thresholds without overriding difficulty.

- [ ] **Step 2: Run focused tests and confirm failure**

  Run `npm test -- --run tests/ai/aiEngine.test.ts tests/ai/informationBoundary.test.ts`.

- [ ] **Step 3: Implement public context and heuristic policy**

  Level 1 uses hand-strength thresholds; levels 2-3 add position, pot odds, draws and C-Bet; levels 4-5 add opponent VPIP/PFR/3-Bet/fold tendencies, fold equity, polarized sizing and value/bluff balance. Use only visible action history and a supplied RNG.

- [ ] **Step 4: Verify tests and deterministic replay**

  Run focused tests plus `npm test`; run a seeded 100-hand comparison showing distinct decision distributions by level without changing the deck.

- [ ] **Step 5: Commit**

  Commit `feat: add bounded information-safe poker AI`.

### Task 6: Career economy, unlocks, statistics, and hand history

**Files:**
- Create: `poker-game/src/career/tableLevels.ts`, `poker-game/src/career/careerState.ts`, `poker-game/src/career/careerService.ts`, `poker-game/src/career/statistics.ts`, `poker-game/src/career/handHistory.ts`
- Create: `poker-game/tests/career/careerService.test.ts`, `poker-game/tests/career/statistics.test.ts`

**Interfaces:**
- Consumes: Task 4 `SettlementResult`, Task 3 `GameState` and action history.
- Produces: `createCareer(nickname): CareerState`, `buyIn(career, level): BuyInResult`, `leaveTable(career, tableStack): CareerState`, `recordHand(career, summary): CareerState`, `applyBankruptcyProtection(career): CareerState`, `getTableAvailability(career): TableAvailability[]`.

- [ ] **Step 1: Write failing career tests**

  Test default 10,000 funds/6-player beginner table; exact five level blinds/buy-ins; permanent unlock at 15,000/40,000/100,000/250,000; buy-in and leave-table transfers; bankruptcy at total funds below 5,000 with 5,000 refill; mode/player-count/level statistics and 500-history retention.

- [ ] **Step 2: Run focused tests and confirm failure**

  Run `npm test -- --run tests/career/careerService.test.ts tests/career/statistics.test.ts`.

- [ ] **Step 3: Implement immutable career reducers and summaries**

  Keep career funds separate from table stacks, make settlement application idempotent by `handId`, and store data needed for VPIP/PFR/3-Bet without requiring those displays in V1.0.

- [ ] **Step 4: Verify focused and full tests**

  Run focused files and `npm test`.

- [ ] **Step 5: Commit**

  Commit `feat: add career funds unlocks and statistics`.

### Task 7: IndexedDB saves, backups, migrations, and resume snapshots

**Files:**
- Create: `poker-game/src/storage/database.ts`, `poker-game/src/storage/saveSystem.ts`, `poker-game/src/storage/migrations.ts`, `poker-game/src/types/persistence.ts`
- Create: `poker-game/tests/storage/saveSystem.test.ts`, `poker-game/tests/storage/migrations.test.ts`

**Interfaces:**
- Consumes: Task 3 `GameState`/`HandSnapshot`, Task 6 `CareerState`.
- Produces: `saveCareer(snapshot): Promise<void>`, `loadCareer(): Promise<LoadResult>`, `saveHandSnapshot(snapshot): Promise<void>`, `loadHandSnapshot(): Promise<HandSnapshot | null>`, `migrateSave(data): VersionedSave`.

- [ ] **Step 1: Write failing IndexedDB tests**

  Use `fake-indexeddb` to test all save points, backup rotation, corrupt-current fallback, both-corrupt recovery error, version migration, 500-hand trimming, and `restoresHandWithoutRedealing` at Pre-Flop/Flop/Turn/River/All-in/side-pot states.

- [ ] **Step 2: Run focused tests and confirm failure**

  Run `npm test -- --run tests/storage/saveSystem.test.ts tests/storage/migrations.test.ts`.

- [ ] **Step 3: Implement stores and atomic save wrapper**

  Create `career`, `currentHand`, `handHistory`, and `settings` object stores; write the current record and previous valid backup in one controlled transaction; persist the full ordered deck and deck index before any action can proceed.

- [ ] **Step 4: Verify focused and full tests**

  Run focused files and `npm test`; assert restored JSON equality for all hidden state fields.

- [ ] **Step 5: Commit**

  Commit `feat: add versioned IndexedDB career and hand saves`.

### Task 8: Zustand integration and white minimal Chinese UI

**Files:**
- Create: `poker-game/src/store/gameStore.ts`, `poker-game/src/store/careerStore.ts`, `poker-game/src/store/settingsStore.ts`
- Create: `poker-game/src/components/PokerTable/*`, `poker-game/src/components/ActionPanel/*`, `poker-game/src/components/PlayingCard/*`, `poker-game/src/components/PotDisplay/*`, `poker-game/src/pages/*`, `poker-game/src/App.tsx`, `poker-game/src/main.tsx`, `poker-game/src/styles/theme.css`
- Create: `poker-game/tests/ui/renderSmoke.test.tsx`

**Interfaces:**
- Consumes: Task 3 engine commands, Task 5 AI actions, Task 6 career selectors, Task 7 save system.
- Produces: Chinese pages for Home, Career, TableSelect, Game, Statistics, History, Settings; bottom action controls that dispatch only legal actions.

- [ ] **Step 1: Write failing render and interaction tests**

  Render the home page, default career summary, table selection fields, table seats, D/SB/BB labels, pot/side-pot text, Chinese action buttons, and disabled invalid bet submission. Verify English labels are only auxiliary.

- [ ] **Step 2: Run the UI test and confirm failure**

  Run `npm test -- --run tests/ui/renderSmoke.test.tsx`.

- [ ] **Step 3: Implement the UI shell and CSS variables**

  Use `#FFFFFF`, `#F5F5F5`, `#FAFAFA`, `#111111`, `#666666`, `#E5E5E5` and one blue accent; use 8/12/16px radii, no casino textures, fixed bottom action area, responsive 1280×720 layout, light card animations, and a one-time short-deck notice with “不再提示”.

- [ ] **Step 4: Verify UI test and production build**

  Run `npm test`, `npm run typecheck`, and `npm run build`; expected exit code 0.

- [ ] **Step 5: Commit**

  Commit `feat: add Chinese white minimal poker UI`.

### Task 9: Settings, pause/leave flow, history detail, and README

**Files:**
- Modify: `poker-game/src/pages/History/*`, `poker-game/src/pages/Settings/*`, `poker-game/src/store/settingsStore.ts`, `poker-game/src/App.tsx`
- Create: `poker-game/src/game/timers.ts`, `poker-game/tests/ui/settingsAndResume.test.tsx`, `poker-game/README.md`

**Interfaces:**
- Consumes: Task 7 persistence APIs, Task 8 UI shell, Task 5 AI timer decisions.
- Produces: pause/resume, pending leave after current hand, normal/2X/极速 AI timing, sound/animation/all-in confirmation settings, history detail timeline, and copy-pasteable README commands.

- [ ] **Step 1: Write failing flow tests**

  Test pause freezing AI, leave-table deferral during a hand, immediate leave between hands, continuation preference when a snapshot exists, settings persistence, history detail fields, and short-deck prompt suppression.

- [ ] **Step 2: Run focused tests and confirm failure**

  Run `npm test -- --run tests/ui/settingsAndResume.test.tsx`.

- [ ] **Step 3: Implement timers, settings, history detail, and README**

  AI timers must be cancelable on pause and restored from state, never from hidden future cards. README must document installation, dev, build, test, local-only storage, migration/backup behavior, architecture, and the no-network guarantee.

- [ ] **Step 4: Verify full suite and build**

  Run `npm test`, `npm run typecheck`, `npm run build`; expected zero failures.

- [ ] **Step 5: Commit**

  Commit `feat: finish resume settings history and documentation`.

### Task 10: Continuous simulation, audit regression, and release gate

**Files:**
- Create: `poker-game/src/simulation/runSimulation.ts`, `poker-game/tests/simulation/continuousSimulation.test.ts`, `poker-game/tests/release/acceptance.test.ts`
- Modify: `poker-game/package.json`, `poker-game/README.md`

**Interfaces:**
- Consumes: Tasks 2-9 public APIs.
- Produces: `runSimulation({ mode, hands, seed, tableSize }): SimulationReport` and npm script `npm run test:simulation`.

- [ ] **Step 1: Write failing simulation and acceptance tests**

  Add standard 6-player and short-deck 6-player simulations of at least 1,000 hands each; assert no deadlock, no negative chips, no illegal action, no unclaimed pot, conserved chips, and deterministic same-seed output. Add acceptance checks for all table sizes, all five levels, both modes, bankruptcy, resume, and recent-history limit.

- [ ] **Step 2: Run simulation tests and confirm failure**

  Run `npm test -- --run tests/simulation/continuousSimulation.test.ts tests/release/acceptance.test.ts`.

- [ ] **Step 3: Implement seeded simulation and release checks**

  Run AI-only hands through the same engine path as the UI, inject seeded RNG, and fail fast with hand ID, state, action history and chip totals when an invariant breaks.

- [ ] **Step 4: Run the complete release verification**

  From `poker-game/`, run `npm install`, `npm run typecheck`, `npm test`, `npm run test:simulation`, and `npm run build`. All commands must exit 0; inspect the final bundle for accidental network fetches and inspect the UI at 1280×720 on macOS/Windows browsers.

- [ ] **Step 5: Commit**

  Commit `test: add v1 release simulation and acceptance gate`.

## Plan Self-Review

- **Spec coverage:** Tasks 2-4 cover cards, standard/short evaluation, betting, dealer order, All-in, side pots and Split Pot; Task 5 covers five AI levels, information boundaries and table-size adaptation; Task 6 covers career funds, unlocks, bankruptcy, statistics and 500-hand history; Tasks 7 and 9 cover IndexedDB, backups, migrations, resume, pause, settings and history detail; Task 8 covers Chinese white UI; Task 10 covers continuous simulation, README commands and release gates.
- **Step scan:** Every task has a failing test, a failure command, one implementation boundary, a passing verification command and a commit. No step depends on an unnamed function or an unreviewed UI-side rule.
- **Type consistency:** Later tasks consume the named signatures from earlier tasks: `GameState`/`HandSnapshot`, `HandEvaluation`, `LegalActionSet`, `SettlementResult`, `CareerState`, and the four persistence functions.
- **Review focus:** The five highest-risk uncovered inputs are pinned to Tasks 2, 3, 4, 5 and 7 in the header and each has a named test.
- **Proportion:** The plan is phased around independently testable deliverables; the UI and storage never own poker rules, and no networking or unrelated product work is included.
