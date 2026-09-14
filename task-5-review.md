# Task 5 Review

## Findings

1. High: the public list route does not validate archived report metadata before returning it, so malformed or sensitive strings stored in `seller_intelligence_reports` can still leak through `/api/public/seller-intelligence`.
   - Evidence: [web/lib/seller-intelligence.ts](C:/Users/ASUS/Documents/亚马逊bestseller榜单监控/.worktrees/seller-intelligence-center/web/lib/seller-intelligence.ts:204) returns `rows.results` directly from D1, and [web/app/api/public/seller-intelligence/route.ts](C:/Users/ASUS/Documents/亚马逊bestseller榜单监控/.worktrees/seller-intelligence-center/web/app/api/public/seller-intelligence/route.ts:10) serializes that array without revalidation or key filtering.
   - Why it matters: Task 5’s brief and test naming both say the public surface should “list and read only validated seller intelligence reports,” but only the detail path revalidates JSON. A corrupted `key`, `generator_version`, or other selected field in the list rows would be returned as-is.

2. Medium: the live seller-intelligence route maps any D1/read-model failure to `404 not_found`, which regresses the existing public live-route behavior and makes transient availability failures look like a missing resource.
   - Evidence: [web/app/api/public/seller-intelligence/live/route.ts](C:/Users/ASUS/Documents/亚马逊bestseller榜单监控/.worktrees/seller-intelligence-center/web/app/api/public/seller-intelligence/live/route.ts:7) catches every error and returns `{ error: "not_found" }` with status `404`.
   - Comparison point: the sibling public live analysis route returns `503 unavailable` on backend failure at [web/app/api/public/analysis/live/route.ts](C:/Users/ASUS/Documents/亚马逊bestseller榜单监控/.worktrees/seller-intelligence-center/web/app/api/public/analysis/live/route.ts:9).
   - Why it matters: the task asked for safe live reads from verified D1 data with no fallback fabrication. Returning a safe error is fine, but `404` incorrectly signals “this report key does not exist” instead of “the live read is temporarily unavailable,” which can mislead callers and defeat retry behavior.

## Spec Verdict

Partially meets spec.

- Confirmed: live reads verified D1 data through `loadVerifiedDashboardFromStore(createD1DashboardStore(db))` with no schema writes or seed fallback on this path.
- Confirmed: seller-alert output is gated on complete Top 30 current/baseline data, competition-strategy stays in disclosure mode below 5 complete market days, archived detail revalidates stored JSON against the contract, and the focused Task 5 tests pass.
- Not fully met: the list endpoint does not actually enforce “validated reports only,” and the live endpoint’s failure contract is weaker than the existing public live-route convention.

## Quality Verdict

Mixed.

- The core read-model logic and the `live-dashboard-data` refactor look sound; I did not find a regression in the extracted verified-store loader itself.
- The package-resolution build/lint failures described in `task-5-report.md` still look environmental from this diff. I did not see any Task 5 code change that would introduce the unresolved `vinext` or `eslint` package issues.

## Verification

- Ran the focused suite:
  - `node --test tests/seller-intelligence-public-routes.test.mjs`
  - Result: 6/6 passing.
- Reviewed the touched route/service files plus the `live-dashboard-data` refactor against the Task 5 brief and existing public route patterns.
