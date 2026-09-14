# V2.2.6 Market Isolation Implementation Plan

> Execute inline with executing-plans and test-driven-development; preserve existing dirty work and avoid parallel agents under the user's low-token constraint.

**Goal:** Single-market recovery must preserve other markets and retain truthful receipt/report provenance.

**Architecture:** Extend existing capture, bundle and report contracts. Add category-level receipt storage without backfilling or rewriting historical snapshots. Legacy whole-day batches remain compatible; a mixed-provenance day must not authorize a whole-day report using one category's receipt.

**Tech Stack:** Existing PowerShell/Python pipeline, TypeScript Worker, D1/Drizzle.

**Spec:** V2.2.6 pasted PRD (`79b67d97-5aac-4a5c-aeb5-e3f0b52b347a/pasted-text.txt`) and explicit user approval to coordinate receipt/sync/report isolation.

## Constraints

- Preserve Pacific Market Date, raw ranks, historical files, trusted-brand conflict guards and complete-day validation.
- No second crawler, database replacement, synthetic market date or partial-production trial.
- P1 remains gated on P0; test before deploying schema/query changes.

## 1. Atomic category persistence

Files: `web/db/schema.ts`, new generated migration, `web/lib/d1.ts`, `web/lib/sync-contract.ts`, `web/app/api/sync/v1/bundles/route.ts`, `web/tests/sync-bundle-route.test.mjs`.

- [ ] Regression: import three markets then one; `SELECT COUNT(*) FROM observations` remains 90 and untouched market rows remain byte-equivalent.
- [ ] Regression: incomplete/stale same-day retry cannot downgrade a complete market; duplicate category keys return 400 before writes.
- [ ] Add per-category receipt/observation-time records and atomic conflict guard; update only supplied category rows. Derive aggregate completeness from persisted categories.
- [ ] Whole-day receipt stays usable only when all categories share its provenance; mixed-day marker must fail closed for old aggregate report authorization.
- [ ] Run bundle/contract/migration tests and inspect generated SQL; never edit applied migrations.

## 2. Receipt-bound reports

Files: existing analysis-reports and seller-intelligence routes/contracts/tests, shared receipt query helper if required.

- [ ] Test category A receipt cannot authorize category B or global overview.
- [ ] Add explicit category-scoped report bundle support; retain old four-report cohort contract.
- [ ] Legacy records fall back to old day receipt only where no category-level provenance exists.
- [ ] Atomic report writes reject stale receipts, including races between preflight and write.

## 3. Existing collection and publisher integration

Files: existing collector, capture receipt module, sync bundle builder, daily orchestration and publisher plus their existing tests.

- [ ] Test one failed source does not discard another source's complete validated observations.
- [ ] Preserve attempt artifacts; authorize only individually complete category cohorts using registry-owned source definitions.
- [ ] Route scheduled/manual recovery through the same existing entrypoint; scope report generation and publication to authorized receipts.
- [ ] Failure remains non-valid and cannot create Exit/Turnover/Contraction; retain old full-batch path.

## 4. Acceptance

- [ ] Relevant regression, lint, production build; additive migration inspection.
- [ ] Publish only verified source following existing Sites access approval flow.
- [ ] Record pre/post production dates, receipts/counts, public API and browser result. Do not pass the new-date gate on an idempotent same-day retry.
- [ ] Verify enabled next schedule and retain exact unresolved issues. P1 only after P0 PASS.
