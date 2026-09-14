# Amazon BS Market Radar V2 Phase 1 Data Semantics Design

## Status

- Date: 2026-08-27
- Scope: Phase 1 only
- Approved direction: preserve the existing crawler and raw ranking history; add a separate Best Sellers product metadata dimension; use verified brand inputs only; treat unverified brands as `Unknown`.
- Prerequisite: `docs/audits/V2-PHASE-0-AUDIT-2026-08-27.md`

## Goal

Establish one auditable semantic foundation for Market Context, Product Classification, Brand Normalization, and Valid Market Days without changing the meaning of Raw Amazon Rankings or implementing any Phase 2 intelligence metric.

Phase 1 is successful when PostgreSQL, the dashboard sync bundle, D1, and shared TypeScript analysis code agree on:

1. which market a record belongs to;
2. which analytical segment an ASIN belongs to;
3. which normalized brand is supported by verified evidence;
4. which market dates may be used as adjacent historical comparison points.

## Non-Goals

Phase 1 does not implement:

- 3D/7D/30D trends;
- Rising, Falling, Presence, Stability, Review Momentum, Turnover, Volatility, or Brand Concentration;
- the V2 Signal schema or Alerts UI;
- the V2 navigation, Overview, Market, Products, Brands, Compare, or Data Status pages;
- sales, revenue, market-share, demand, or causal estimates;
- machine-learning classification;
- title-based brand guessing;
- removal or redirection of legacy pages;
- crawler rewrites.

## Design Principles

- Raw Ranking remains an immutable representation of the collected Amazon Best Sellers list.
- Analytical Market is a filtered view produced from product metadata; it never deletes or rewrites raw observations.
- Missing metadata remains unknown. Unknown is a valid result, not an error to conceal.
- One implementation defines each semantic rule. Pages, APIs, reports, and signals must consume it rather than recalculate it.
- Rules are versioned and explainable.
- Historical comparisons use valid market days, not natural calendar adjacency.
- Existing snapshots, receipts, reports, and database rows remain readable.

## Architecture

Phase 1 introduces four focused semantic units:

1. **Market Context Catalog** — defines supported marketplace/category/segment combinations and URL-safe identifiers.
2. **Product Classifier** — maps verified title/category inputs to a product type, confidence, matched rule, and rule version.
3. **Brand Normalizer** — maps a verified raw brand through an auditable alias catalog; absent inputs return Unknown.
4. **Valid Market Day Selector** — selects dates that satisfy both persisted completeness evidence and an exact Top30 validation.

A separate **Best Sellers Product Metadata Dimension** stores classification and verified brand results by Marketplace + ASIN. It is synchronized to D1 independently of daily ranking observations.

Derived Phase 2 metrics are not stored in this dimension.

## 1. Market Context

### Canonical Type

```ts
type MarketplaceCode = "US";

type CategoryKey =
  | "pressure_washers"
  | "sump_pumps"
  | "pressure_washer_accessories";

type SegmentKey =
  | "all_bestsellers"
  | "machines"
  | "electric"
  | "gas"
  | "cordless"
  | "accessories";

type MarketContext = {
  marketplace: MarketplaceCode;
  category: CategoryKey;
  segment: SegmentKey;
};
```

`US` is the public Market Context identifier. Persistence and sync continue to use the existing internal marketplace key `AMAZON_US`; one catalog mapping converts between them. This avoids rewriting existing snapshot identity while keeping the public URL concise.

### Supported Combinations

Pressure Washers supports:

- `all_bestsellers`
- `machines`
- `electric`
- `gas`
- `cordless`
- `accessories`

Sump Pumps and Pressure Washer Accessories support `all_bestsellers` in Phase 1. Their future segment values are not advertised until classification rules and product requirements exist.

### URL Contract

Business APIs and future pages use:

```text
?marketplace=US&category=pressure_washers&segment=machines
```

Missing values resolve to:

```text
US / pressure_washers / machines
```

Unknown or unsupported combinations return a validation error at API boundaries; they do not silently fall back to another market.

### Filtering Semantics

- `all_bestsellers`: no product-type filtering;
- `machines`: electric, gas, and cordless pressure washers;
- `electric`: electric pressure washers only;
- `gas`: gas pressure washers only;
- `cordless`: cordless pressure washers only;
- `accessories`: all supported accessory types; `unknown` is excluded.

Raw `/rankings` data does not apply these filters.

## 2. Product Classification

### Product Types

```ts
type ProductType =
  | "electric_pressure_washer"
  | "gas_pressure_washer"
  | "cordless_pressure_washer"
  | "surface_cleaner"
  | "pressure_washer_gun"
  | "hose"
  | "nozzle"
  | "chemical_cleaner"
  | "pump_protector"
  | "other_accessory"
  | "unknown";

type ClassificationConfidence = "high" | "medium" | "low";
```

### Classifier Result

```ts
type ClassificationResult = {
  productType: ProductType;
  confidence: ClassificationConfidence;
  ruleId: string | null;
  ruleVersion: string;
  evidence: string[];
};
```

### Inputs

The classifier accepts:

- ASIN;
- verified Amazon title;
- raw category key;
- optional existing verified metadata.

It does not accept page component state, report prose, or unverified inferred brand data.

### Rule Ordering

Rules are centralized and evaluated from most specific exclusion to broadest match:

1. accessory rules such as surface cleaner, gun/wand, hose, nozzle, chemical cleaner, and pump protector;
2. cordless machine rules;
3. gas machine rules;
4. electric machine rules;
5. category-constrained `other_accessory` rules;
6. unknown.

Accessory exclusions run before machine rules so a title such as “pressure washer hose” is not classified as a machine merely because it contains “pressure washer.”

### Confidence

- `high`: an explicit, unambiguous phrase or verified metadata identifies the type;
- `medium`: a category-constrained combination of multiple supporting terms identifies the type without contradiction;
- `low`: no safe classification is possible; result must be `unknown`.

Conflicting positive rules resolve to `unknown/low` with all conflict evidence retained. The implementation never chooses the first arbitrary match.

### Rule Versioning

The first V2 rule set uses a stable version such as `product-rules-v1`. Persisted metadata records the version and basis so a later backfill can distinguish old and new classifications.

## 3. Brand Normalization

### Source Policy

Only a verified raw brand is eligible for normalization. Accepted sources may include:

- verified official metadata already collected for the ASIN;
- an explicitly maintained ASIN-to-brand record;
- a reviewed import whose provenance is recorded.

The Amazon Best Sellers title alone is not a brand source.

### Result

```ts
type BrandNormalizationResult = {
  rawBrand: string | null;
  normalizedBrand: string | null;
  normalizedKey: string | null;
  aliasRuleId: string | null;
  source: "verified_metadata" | "manual_review" | "unknown";
};
```

When no verified brand exists:

- `rawBrand = null`;
- `normalizedBrand = null`;
- `normalizedKey = null`;
- UI label is `Unknown` or `品牌未知`;
- the ASIN is excluded from brand-seat numerators in later phases and counted in an explicit Unknown bucket where applicable.

### Alias Rules

Aliases are centralized, case-insensitive after Unicode-safe trim and whitespace normalization. Alias matching does not destructively overwrite `rawBrand`.

Example:

```text
WESTINGHOUSE
Westinghouse Outdoor Power Equipment
Westinghouse
```

normalize to:

```text
Westinghouse
```

Each alias has a stable rule identifier. Ambiguous aliases are rejected from the catalog rather than resolved by order.

## 4. Best Sellers Product Metadata Dimension

### PostgreSQL Shape

The new dimension is logically equivalent to:

```text
best_sellers_product_metadata
  marketplace_code
  asin
  product_type
  classification_confidence
  classification_rule_id
  classification_rule_version
  classification_evidence_json
  raw_brand
  normalized_brand
  normalized_brand_key
  brand_alias_rule_id
  brand_source
  first_seen_market_date
  last_seen_market_date
  created_at
  updated_at
```

Primary key: `(marketplace_code, asin)`.

`first_seen_market_date` and `last_seen_market_date` are observation facts derived from verified Best Sellers history. `first_seen_market_date` means the first date observed by this system and must be labeled “首次发现,” never “新品.”

The raw daily `best_sellers_observation` table is unchanged.

### D1 Shape

D1 receives a corresponding `product_metadata` table keyed by Marketplace + ASIN. Daily `observations` remain unchanged. This avoids repeating product classification and brand values for every market date.

### Update Rules

- First seen may move earlier during a historical backfill but never later.
- Last seen may move later but never earlier.
- A higher-confidence classification may replace a lower-confidence classification when the rule version and evidence are recorded.
- A verified brand may replace Unknown.
- Unknown or lower-quality inputs cannot overwrite an existing verified brand.
- A brand correction is an explicit reviewed update; it is not inferred from title changes.

## 5. Valid Market Day

### Category-Level Definition

A category date is valid only when all conditions are true:

1. a verified snapshot receipt exists for the date;
2. the persisted category completeness flag is true;
3. the actual observations contain exactly 30 records;
4. ranks are exactly 1 through 30 with no duplicates or gaps;
5. there are exactly 30 unique, valid ASINs.

Price, Rating, Reviews, and Discount coverage do not determine ranking-day validity. Those fields have independent coverage gates for their own analyses.

### Market-Level Definition

A market date is valid for a selected context when its underlying raw category date is valid. Analytical segment size may be below 30 after classification; that does not invalidate the raw category day.

Cross-category Overview metrics may require all selected raw categories to be valid. The caller must state whether it needs category-level or multi-category validity.

### Previous Valid Day

The previous comparison baseline is the latest earlier valid date in the same Market Context, not the immediately preceding calendar date and not merely the immediately preceding stored snapshot.

For the verified local history:

```text
2026-08-18 -> 2026-08-20
```

is an adjacent valid-market-day pair because 2026-08-19 failed and produced no verified snapshot.

### Incomplete Data Behavior

- A failed or partial current day cannot generate Exit, Entry, Re-entry, or Rank Change.
- Missing Price/Rating/Reviews remains null.
- A missing category day is not an empty Top30.
- If fewer valid days exist than a requested window requires, the later Intelligence Layer must return a limited sample and evidence status rather than inventing dates.

### Consistency Changes

Phase 1 must align:

- PostgreSQL views/queries;
- local PowerShell Seller Intelligence history selection;
- website `live-dashboard-data` history selection;
- public rankings baseline behavior;
- product history inputs used by later metrics;
- Methodology copy and tests.

## 6. Data Flow

1. Existing crawler writes the raw snapshot unchanged.
2. Existing receipt verifies raw category completeness.
3. Snapshot import preserves raw observations.
4. Metadata backfill/upsert calculates first/last seen and rule-based classification.
5. Verified brand input, when available, passes through the Brand Normalizer and updates metadata without overwriting raw evidence.
6. Dashboard sync bundle includes a versioned product metadata cohort for all ASINs referenced by the snapshot.
7. D1 atomically writes snapshot/category/observation/discount/product-metadata data under the existing receipt-bound transaction.
8. Public analysis queries resolve Market Context, select valid raw category days, join product metadata, then form the Analytical Market.
9. Raw Ranking queries skip the metadata filter and continue returning every collected ASIN.

## 7. Sync Contract

The Dashboard Bundle schema receives a new version rather than silently changing the meaning of v1. The versioned payload includes:

```ts
type ProductMetadataSyncRow = {
  marketplace: "AMAZON_US";
  asin: string;
  productType: ProductType;
  classificationConfidence: ClassificationConfidence;
  classificationRuleId: string | null;
  classificationRuleVersion: string;
  classificationEvidence: string[];
  rawBrand: string | null;
  normalizedBrand: string | null;
  normalizedBrandKey: string | null;
  brandAliasRuleId: string | null;
  brandSource: "verified_metadata" | "manual_review" | "unknown";
  firstSeenMarketDate: string;
  lastSeenMarketDate: string;
};
```

Contract validation rejects:

- unsupported marketplace/category/segment values;
- invalid ASIN or dates;
- confidence/type combinations such as `unknown/high`;
- a normalized brand without a raw verified brand;
- first seen after last seen;
- duplicate Marketplace + ASIN rows;
- metadata ASINs not present in the intended synchronized cohort when the bundle declares a complete cohort.

Older v1 bundles remain readable for historical recovery. Missing metadata in v1 maps to unknown and does not fabricate classification or brand.

## 8. Error Handling

- Rule conflict: return `unknown/low` with conflict evidence.
- Missing brand: return Unknown, not an exception.
- Invalid alias catalog: fail startup/test validation before applying aliases.
- Metadata write failure: fail the metadata-inclusive sync transaction; do not expose a snapshot whose declared metadata cohort was only partially written.
- D1 unavailable: V2 business analysis returns an explicit unavailable/data-status state. The fixed repository seed may remain a development/test fixture but must not generate production “today” signals.
- Backfill interruption: use idempotent upserts; preserve raw snapshots and existing verified metadata.
- Unsupported Market Context: return a typed validation error; do not redirect silently.

## 9. Migration Strategy

### PostgreSQL

- Add a new numbered migration; never modify existing migrations 001–011.
- Create the metadata table and constraints first.
- Backfill first/last seen and classification from verified `best_sellers_daily_current` history.
- Leave Brand null unless a verified source exists.
- Add valid-category-day and previous-valid-day query primitives without redefining Raw Ranking views.
- Do not delete legacy opportunity, market-structure, or rank-influence tables.

### D1

- Add a new Drizzle migration and generated snapshot.
- Update `web/db/schema.ts` and the runtime compatibility path in `ensureSchema`.
- Migration is idempotent over existing D1 databases.
- Existing observation and report tables remain intact.

### Rollback

Raw snapshots and raw observations remain usable if the new metadata layer is disabled. Because Phase 1 only adds a separate dimension and query semantics, rollback does not require rewriting historical observations.

## 10. Testing Strategy

Implementation follows test-driven development. Each behavior is first represented by a failing test and then receives the minimum implementation.

### Product Classification

- Electric machine;
- Gas machine;
- Cordless machine;
- Surface Cleaner;
- Gun/Wand;
- Hose;
- Nozzle;
- Chemical Cleaner;
- Pump Protector;
- Other Accessory;
- Unknown;
- accessory wording wins over broad machine wording;
- conflicting rules return unknown/low;
- rule version and evidence are stable.

### Brand

- exact canonical brand;
- case and whitespace normalization;
- alias normalization;
- absent verified brand returns Unknown;
- ambiguous alias catalog is rejected;
- title alone never supplies a brand;
- lower-quality input cannot overwrite an existing verified brand.

### Market Context

- default context;
- every supported Pressure Washers segment;
- unsupported category/segment rejection;
- raw ranking bypasses Analytical Market filters;
- Machines includes electric/gas/cordless only;
- Accessories excludes unknown.

### Valid Market Day

- exact Top30 is valid;
- persisted incomplete flag overrides otherwise exact rows;
- partial/missing/duplicate rank/duplicate ASIN is invalid;
- missing Price/Rating/Reviews does not invalidate ranking day;
- failed 2026-08-19 is skipped between valid 08-18 and 08-20;
- no Entry/Exit/Rank comparison is emitted from an invalid current day;
- product history excludes observations from invalid category days.

### Schema and Sync

- PostgreSQL migration structure and constraints;
- D1 migration applies twice over a legacy schema;
- v2 bundle accepts a complete metadata cohort;
- v2 bundle rejects duplicate/invalid/inconsistent metadata;
- v1 bundle remains compatible and maps metadata to unknown;
- atomic D1 write includes metadata;
- metadata upsert preserves first seen and verified brand rules.

### Regression

- existing Pester suite;
- existing Python collector suite;
- existing Web Node suite;
- vinext production build;
- ESLint.

## 11. Deliverables

Phase 1 delivers:

- a versioned Market Context catalog and parser;
- a centralized, versioned Product Classifier;
- a centralized Brand Normalizer and validated alias catalog;
- PostgreSQL and D1 product metadata dimensions with migrations;
- a versioned metadata-inclusive dashboard sync contract;
- one Valid Market Day selector used by the website and mirrored by local report logic;
- historical metadata backfill behavior;
- Methodology updates describing the exact semantics;
- full core tests and regression verification.

Phase 1 does not deliver new V2 business pages. After its tests pass, work stops for Phase 1 review before Phase 2 begins.

## 12. Acceptance Criteria

1. Raw Ranking results are byte-for-byte semantically unchanged apart from optional joined metadata returned separately.
2. Pressure Washer machine/accessory segmentation is deterministic, versioned, explainable, and permits Unknown.
3. No brand is inferred from title; absent verified brand is visibly Unknown.
4. PostgreSQL and D1 store one product metadata record per Marketplace + ASIN.
5. 2026-08-18 and 2026-08-20 are selected as adjacent valid days when 2026-08-19 is failed.
6. Invalid current days cannot create rank, entry, exit, or re-entry facts.
7. Existing historical snapshots and v1 sync bundles remain readable.
8. All new semantic functions have tests that were observed failing before implementation.
9. Existing PowerShell, Python, and Web tests remain green; website build and lint pass.
10. No Phase 2 metric, new V2 page, crawler rewrite, or legacy-page removal is included.
