# Task 3 Fix 1 Re-review

## Result

P1: ADDRESSED.

`Read-DashboardPublishState` now rejects a `PUBLISHED` state when either `ObservationCount` or `ReportsUploaded` is null or cannot be parsed as an integer. Because recovery only returns `SKIPPED_ALREADY_PUBLISHED` for a non-null state with `Status -eq 'PUBLISHED'`, malformed counter state is treated as invalid and recovery invokes the publisher instead.

The added regression test, `does not skip recovery for non-numeric published counters`, writes a malformed `PUBLISHED` record, asserts recovery does not return `SKIPPED_ALREADY_PUBLISHED`, and verifies the publisher is called once.

## Verification

- Focused test: `tests/DashboardPublishState.Tests.ps1`
- Result: 8 passed, 1 failed.
- The new regression test passed. The lone failure is the existing `writes a sanitized FAILED state before rethrowing a primary publication error` test; it is outside this fix's changed files and does not exercise counter validation.

The requested `task-3-brief.md`, `task-3-report.md`, `task-3-review.md`, and `task-3-fix1-review-package.md` files were not present at the supplied worktree paths during re-review.

## New breakage

None identified in this fix.
