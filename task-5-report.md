# Task 5: safe live and archive read models report

Date: 2026-08-25 (China Standard Time)

## Delivered

- Added `web/lib/seller-intelligence.ts` to build public seller-intelligence read models from verified dashboard data, validate list/live query inputs, revalidate archived JSON, and keep database failures in safe public states.
- Added public seller-intelligence routes:
  - `web/app/api/public/seller-intelligence/route.ts`
  - `web/app/api/public/seller-intelligence/[...key]/route.ts`
  - `web/app/api/public/seller-intelligence/live/route.ts`
- Added `web/tests/seller-intelligence-public-routes.test.mjs` and wired it into `web/package.json`.
- Refactored `web/lib/live-dashboard-data.ts` to export a verified-store loader so the live seller-intelligence route can read D1 without schema writes or seed fallback.

## Verification

1. Focused Task 5 test file:

   ```powershell
   & 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' --test .\tests\seller-intelligence-public-routes.test.mjs
   ```

   Result: exit code `0`; all `6` tests passed.

2. Broader direct Node test batch after `pnpm test` failed because `node` was not on PATH inside this shell:

   ```powershell
   $env:PATH='C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin;' + $env:PATH
   & 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/fallback/pnpm.cmd' test
   ```

   Result: the first Node test phase completed successfully with `41` passing tests and `0` failures, including the new seller-intelligence route tests, existing live dashboard tests, existing analysis/public contract tests, and existing seller-intelligence contract/sync tests.

## Outstanding environment blockers

- `vinext build` still fails in this worktree because `worker/index.ts` cannot resolve `vinext/server/image-optimization`, and `vite.config.ts` also reports unresolved package imports during the same build path. This blocked the post-build route/render test phase.
- Direct ESLint execution is also blocked by the worktree's package-resolution issue: `eslint.config.mjs` cannot resolve package `eslint` from the current `node_modules` layout.

These blockers were observed during verification and were not introduced by Task 5 route/service code.

## Round 1 review fixes

- Added strict public metadata filtering for `/api/public/seller-intelligence`, so malformed or unsafe archive rows are omitted unless `key`, `report_kind`, `profile`, `market_date`, `category_key`, `generated_at`, `generator_version`, and `content_sha256` all match the safe public contract.
- Changed `/api/public/seller-intelligence/live` backend/read failures to return `503 unavailable` instead of `404 not_found`.

### Round 1 verification

```powershell
& 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' --test .\tests\seller-intelligence-public-routes.test.mjs
```

Result: exit code `0`; `7` passing, `0` failing.

## Round 2 controller-ruling fix

- Updated `web/lib/seller-intelligence-contract.ts` so `seller-alert/daily/<date>/overview.json` is valid when and only when `categoryKey` is `null`.
- Kept exact scope consistency intact: overview reports reject non-null category keys, and scoped category reports reject `null`.
- Confirmed the archived-list metadata validator stays aligned with the same rule, so valid seller-alert overview rows remain public while mismatched overview/category rows are omitted.

### Round 2 verification

```powershell
& 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' --test .\tests\seller-intelligence-contract.test.mjs
& 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' --test .\tests\seller-intelligence-public-routes.test.mjs
```

Result:
- contract suite: exit code `0`; `8` passing, `0` failing
- public-route suite: exit code `0`; `7` passing, `0` failing
