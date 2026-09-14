# V2 Brand Evidence and Historical Backfill Design

- Date: 2026-08-28
- Status: Approved direction; implementation pending
- Scope: trusted brand evidence acquisition, normalization handoff, historical ASIN backfill, and metadata refresh
- Out of scope: Brand UI, Brand Intelligence metrics, Market Context UI, V2 Intelligence Engine, crawler rewrite, account/auth changes

## 1. Goal

Replace the current effective brand coverage of `0 / 131` with an auditable, conservative brand enrichment path that:

- captures a brand only from explicit public Amazon product-detail evidence;
- verifies that the detail page belongs to the requested ASIN;
- keeps `raw_brand` separate from `normalized_brand`;
- never infers a brand from the product title;
- leaves unverifiable products as `unknown`;
- enriches future captures without another detail-page pass;
- backfills historical ASIN metadata without rewriting immutable ranking snapshots.

## 2. Non-Negotiable Truth Boundaries

1. A brand is eligible only when the public detail page exposes an explicit brand-labelled value or another approved structured brand field.
2. The detail page ASIN must match the requested ASIN before any extracted brand is accepted.
3. Product titles, URL slugs, seller names, manufacturer guesses, recommendation cards, and search snippets are not brand evidence.
4. Blocked, login, CAPTCHA, unavailable, malformed, conflicting, or ASIN-mismatched pages produce `unknown` rather than a guessed value.
5. `raw_brand` preserves the cleaned explicit brand value. Alias normalization produces `normalized_brand`; it never overwrites the raw value.
6. Brand aliases remain centrally configured and versioned in `config/v2-brand-aliases.json`.
7. Existing ranking snapshots and capture receipts are immutable. Historical brand backfill updates only product metadata through a separate receipt-bearing enrichment artifact.
8. Brand enrichment failure must not invalidate an otherwise complete Top30 ranking capture. Brand is optional metadata, not a ranking completeness gate.

## 3. Chosen Approach

### 3.1 Reuse the existing detail-page visit

The collector already opens every product detail page to verify discount state. The brand extractor will run against the same `_extract_detail_page` result, so future collection does not add another browser tab, navigation, or network pass.

The extractor will add a structured candidate to the detail-page result. The verification layer accepts it only after `_is_verified_detail_identity` confirms the ASIN.

### 3.2 Accept only explicit structured evidence

Initial accepted evidence sources, in priority order:

1. Product overview rows whose normalized label is exactly `brand`;
2. Product details table rows whose normalized header is exactly `brand`;
3. Detail bullets that expose an explicit `Brand` label/value pair.

The first release will not accept `#bylineInfo` text such as “Visit the X Store”. It can refer to a store or marketing identity rather than a verified brand field. This conservative choice may reduce coverage but prevents false brand attribution.

If more than one accepted structured source is present:

- identical cleaned values produce one verified candidate;
- case/whitespace-only differences produce one verified candidate while preserving the highest-priority raw value;
- materially different values produce a conflict and therefore `unknown`.

### 3.3 Preserve provenance outside immutable ranking snapshots

Future observations may carry:

```json
{
  "raw_brand": "Westinghouse",
  "brand_source": "verified_metadata"
}
```

The daily diagnostic receives a sanitized brand-evidence entry with:

```json
{
  "category_key": "pressure_washers",
  "asin": "B0BVGSX46M",
  "detail_url": "https://www.amazon.com/dp/B0BVGSX46M",
  "verification_status": "VERIFIED",
  "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD"
}
```

No page HTML, cookies, session information, free-form error message, or secret is persisted.

Historical backfill writes a separate artifact under:

```text
var/brand-enrichment/YYYY-MM-DD/amazon-brand-enrichment.json
var/brand-enrichment/YYYY-MM-DD/amazon-brand-enrichment-receipt.json
```

The artifact is append-oriented and keyed by marketplace + ASIN. It contains the same sanitized evidence fields plus the explicit raw brand when verified. The receipt binds:

- schema version;
- generated timestamp;
- requested ASIN set hash;
- artifact SHA-256;
- verified/missing/conflict counts.

The artifact never modifies historical `amazon-bestsellers.json` files or their receipts.

## 4. Data Contracts

### 4.1 Detail extraction result

The internal Python detail result gains:

```python
{
    "brand_candidates": [
        {
            "value": "Westinghouse",
            "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
        }
    ]
}
```

Candidate values are cleaned for Unicode whitespace and surrounding punctuation only. Marketing-prefix stripping is not performed because accepted sources already expose a label/value structure.

### 4.2 Brand classification result

A pure Python function converts the extracted detail result into one of:

```python
{
    "raw_brand": "Westinghouse",
    "brand_source": "verified_metadata",
    "verification_status": "VERIFIED",
    "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
}
```

or:

```python
{
    "raw_brand": None,
    "brand_source": "unknown",
    "verification_status": "MISSING" | "CONFLICT" | "IDENTITY_MISMATCH" | "VERIFICATION_BLOCKED",
    "evidence_source": None,
}
```

This function does not normalize aliases. PowerShell remains the only brand-normalization layer.

### 4.3 Ranking observation compatibility

`raw_brand` and `brand_source` are optional observation fields. Old snapshots without these properties remain valid. A verified observation must contain both fields. An unknown observation must have `raw_brand = null` or omit it and must not provide an alias or normalized brand.

### 4.4 Enrichment artifact

The backfill artifact uses `amazon-brand-enrichment-v1` and contains:

```json
{
  "schema_version": "amazon-brand-enrichment-v1",
  "marketplace": "AMAZON_US",
  "generated_at": "2026-08-28T00:00:00Z",
  "products": [
    {
      "asin": "B0BVGSX46M",
      "raw_brand": "Westinghouse",
      "brand_source": "verified_metadata",
      "verification_status": "VERIFIED",
      "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
      "detail_url": "https://www.amazon.com/dp/B0BVGSX46M"
    }
  ]
}
```

Unknown products remain in the artifact with `raw_brand = null`, `brand_source = unknown`, and a bounded verification status. This makes coverage and failures measurable without inventing data.

## 5. Future Capture Data Flow

1. Collect exact Top30 raw ranking cards.
2. Verify ranking completeness and price requirements as today.
3. Visit each detail page for discount verification as today.
4. Extract discount fields and structured brand candidates in the same page evaluation.
5. Verify detail ASIN identity.
6. Classify brand evidence.
7. Attach only `raw_brand` and `brand_source` to the observation.
8. Persist sanitized discount and brand evidence in the daily diagnostic.
9. Create the canonical snapshot and receipt using the existing atomic path.
10. Existing product metadata generation normalizes verified raw brands and keeps unknowns null.
11. PostgreSQL and D1 metadata upserts preserve higher-quality verified brands.

Brand failure does not change collection status from COMPLETE when rank/ASIN/required price gates pass.

## 6. Historical Backfill Data Flow

1. Read the distinct ASIN set from receipt-verified, exact-Top30 historical snapshots.
2. Sort and deduplicate ASINs deterministically.
3. Open each canonical public detail URL in an ephemeral browser context.
4. Apply the same extraction, identity verification, brand classification, and blocked-page rules used by future capture.
5. Write the enrichment artifact atomically.
6. Write and verify its receipt before database work.
7. Convert verified rows through `Get-BestSellersBrandNormalization`.
8. Update PostgreSQL product metadata using the existing quality-preserving upsert.
9. Publish a metadata refresh bundle to D1 without replacing or fabricating ranking observations.
10. Report verified/unknown/conflict/blocked counts and rerun coverage queries.

The backfill is idempotent. Re-running an identical artifact does not lower an existing verified brand or alter first/last seen dates.

## 7. Metadata Refresh Boundary

The existing dashboard bundle requires product metadata to match one snapshot’s ASIN cohort. Historical enrichment spans more than one daily cohort, so it must not be forced through a fake ranking bundle.

A dedicated authenticated metadata refresh endpoint will accept only a receipt-bound `amazon-brand-metadata-refresh-v1` payload. It will:

- require the existing dashboard sync bearer secret;
- validate marketplace, ASIN, raw/normalized brand coherence, source, evidence, and artifact hash;
- update only product metadata rows;
- refuse unknown values that would overwrite verified values;
- merge no ranking, discount, report, or snapshot state;
- return imported/duplicate/conflict-safe public statuses without internal details.

This endpoint is for project-owned backfill and future metadata repair, not a general public write API.

## 8. Normalization Rules

- PowerShell `Get-BestSellersBrandNormalization` remains authoritative.
- Exact/case/whitespace aliases map through `config/v2-brand-aliases.json`.
- A verified raw brand with no alias becomes its own canonical normalized brand after safe trimming; it is not discarded.
- Alias rules must have stable IDs and reject ambiguous normalized aliases.
- Replacing a canonical brand name requires an explicit alias-config version change and tests.
- The raw value remains unchanged in metadata history/audit artifacts.

## 9. Error Handling

| Condition | Result |
| --- | --- |
| Explicit Brand field + matching ASIN | verified_metadata |
| No explicit Brand field | unknown / MISSING |
| Conflicting explicit Brand fields | unknown / CONFLICT |
| Detail ASIN mismatch | unknown / IDENTITY_MISMATCH |
| CAPTCHA/login/access denied | unknown / VERIFICATION_BLOCKED |
| Navigation/extraction exception | unknown / VERIFICATION_BLOCKED |
| Empty/malformed brand value | unknown / MISSING |
| Backfill artifact hash mismatch | stop before database or website update |
| Metadata refresh authentication failure | HTTP 401 with no secret detail |
| Existing verified brand + incoming unknown | retain existing verified brand |
| Existing verified brand + different verified brand | reject as conflict; require manual review |

No brand error may downgrade an otherwise valid ranking observation or fabricate a replacement value.

## 10. File and Module Boundaries

Expected new focused files:

- `scripts/python/brand_evidence.py`: pure candidate cleanup/classification and contract helpers;
- `scripts/Invoke-BestSellersBrandBackfill.ps1`: receipt-verified historical ASIN selection and orchestration;
- `src/BestSellersBrandEnrichment.psm1`: enrichment artifact/receipt validation and metadata-row conversion;
- `web/lib/brand-metadata-refresh-contract.ts`: refresh payload validation;
- `web/app/api/sync/v1/product-metadata/route.ts`: authenticated, atomic metadata-only refresh.

Expected modifications:

- `scripts/python/collect_best_sellers.py`: extract candidates during existing detail visit and attach verified fields;
- `src/BestSellersDataSemantics.psm1`: consume verified enrichment rows without changing title-inference prohibition;
- `src/BestSellersPostgres.psm1`: expose metadata-only import using the existing upsert function;
- `config/v2-brand-aliases.json`: add aliases only after verified raw values are observed;
- relevant Python, Pester, and Node tests.

The design intentionally avoids a new database table unless implementation proves the current metadata table cannot safely express the required merge. Evidence remains in immutable artifacts; database metadata stores the current trusted value.

## 11. TDD and Test Matrix

Every behavior change starts with a failing test.

### Python

- extracts Brand from product overview row;
- extracts Brand from product detail table;
- extracts Brand from labelled detail bullet;
- ignores byline/store text;
- accepts equal candidates across sources;
- rejects conflicting candidates;
- rejects candidate on ASIN mismatch;
- returns unknown for blocked or malformed pages;
- future discount verification attaches brand without a second navigation;
- legacy fixture snapshots remain valid.

### PowerShell

- reads only receipt-verified exact-Top30 historical ASINs;
- writes deterministic enrichment artifacts and receipts atomically;
- refuses hash, ASIN-set, schema, or count mismatch;
- normalizes verified raw brands through audited aliases;
- preserves unknown as all-null brand metadata;
- never derives brand from title;
- metadata-only PostgreSQL upsert preserves existing verified brands;
- rerun is idempotent.

### Website

- validates metadata refresh contract and ASIN uniqueness;
- rejects missing raw/normalized pairs and unknown populated brand fields;
- rejects a payload whose artifact hash does not match;
- authenticates with the existing exact bearer secret;
- writes all metadata rows in one D1 batch;
- retains verified metadata when incoming rows are unknown;
- rejects conflicting verified values without partial writes;
- exposes no internal failure details.

### Full regression

- Windows PowerShell/Pester full suite;
- project `.venv` Python unittest full suite with Playwright tests;
- web full test command and production build;
- ESLint/JSX accessibility lint;
- fresh PostgreSQL brand coverage query;
- public API verification after metadata publish.

## 12. Acceptance Criteria

1. No production brand is inferred from a title, URL slug, seller name, recommendation, or byline store text.
2. Future capture reuses the existing detail-page visit and performs no second brand-only navigation.
3. Every accepted brand is bound to a matching detail ASIN and an approved explicit source.
4. Missing, blocked, mismatched, or conflicting evidence remains unknown.
5. Historical ranking snapshots and capture receipts remain byte-for-byte unchanged.
6. Historical enrichment artifact and receipt verify before any metadata update.
7. PostgreSQL and D1 retain higher-quality verified brands when incoming evidence is unknown.
8. Conflicting verified values do not silently overwrite each other.
9. The backfill is idempotent and reports measurable coverage counts.
10. All new focused tests and existing full suites pass.
11. Brand coverage after backfill is reported as an observed result, not promised in advance.
12. Implementation stops after trusted brand capture/backfill and metadata refresh; Market Context UI is the next separately approved slice.

## 13. Deployment and Rollback

Deployment order:

1. ship compatible website metadata-refresh contract/endpoint;
2. deploy the website and verify existing read paths are unchanged;
3. ship local extraction/backfill tooling;
4. run a small representative backfill cohort and verify artifact/receipt/database merge;
5. run the complete historical ASIN backfill;
6. publish metadata refresh;
7. verify PostgreSQL/D1/public API counts.

Rollback does not delete historical evidence. If a release is invalid:

- stop new backfill runs;
- redeploy the previous website version;
- retain enrichment artifacts for audit;
- correct alias/extraction rules with a new rule version;
- rerun metadata refresh only after tests and conflict review.

No rollback rewrites ranking snapshots or their receipts.
