# V2.2 Final Consistency & Multi-Market Optimization — Design

## Approved outcome

V2.2 retains the current dark SaaS and existing application architecture. It makes data semantics, context, display language, and legacy page behavior consistent across the three existing Amazon US markets.

## Data architecture

`RawCategoryDay` remains the immutable Amazon Top30 for one category and market date. `MarketUniverse` is derived from one raw category day plus the centralized product metadata and a validated `MarketContext`.

```text
independent category source
        ↓
latest requested valid category day
        ↓
RawCategoryDay (never filtered or rewritten)
        ↓ centralized Product Classification
MarketUniverse(category, segment, date)
        ↓
Overview / Market / Products / Brands / Signals / Reports / Alerts
```

For `segment=all`, the universe equals the raw category day. For analytical segments it contains only explicitly allowed classified product types. Unknown never enters a specific segment.

## Classification

Rules use phrase/token boundaries and explicit precedence:

1. unmistakable accessory product identity phrases (surface cleaner, gun, hose, nozzle, pump protector, chemical cleaner),
2. unmistakable machine identity phrases (electric/gas/cordless pressure washer),
3. structured conservative secondary rules,
4. unknown.

Compatibility language such as “for gas and electric pressure washers” does not make an accessory a machine. Multiple compatible accessory features use a deterministic most-specific rule instead of becoming unknown. Ambiguous titles remain unknown.

Rule versions are monotonically compared in both PostgreSQL and D1. A newer same-confidence rule may correct an older classification; lower versions and lower confidence cannot downgrade newer trusted results.

## Context and dates

The URL is the source of truth for `category`, `segment`, and optional `date`. No realtime global/localStorage synchronization is introduced. Navigation inherits the current valid context; each page and browser tab can then diverge independently. Invalid category/segment/date values normalize to the destination page's safe defaults or latest valid date.

## Freshness

The data model distinguishes:

- Latest Crawl: latest recorded collection attempt and outcome,
- Latest Snapshot: latest persisted category snapshot,
- Latest Valid Market Day: latest complete Top30 day eligible for analysis.

Incomplete/failed attempts never participate in Exit, Turnover, rank trend, or brand contraction. When the latest Snapshot is incomplete, analysis selects the latest valid day for that category.

## UI consistency

Existing AppShell, MarketContext, ProductIdentity, SignalCard and tables are reused. Shared display functions become the only page-facing formatters. Rank and delta are separate. Reviews use English compact units. Missing values are em dash. Reports and Alerts receive the same context-aware analytical input as the other business pages.

## Compatibility and safety

- Existing routes remain valid through aliases or normalized redirects.
- Raw snapshots are never rewritten.
- Database changes are additive migrations and idempotent backfill paths.
- Historical category-wide reports are explicitly labelled legacy/category-wide rather than presented as segment-specific.
- No crawler rewrite or new market is introduced.
