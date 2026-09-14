import type { ProductMetadata } from "./product-metadata";

const trustedBrandSources = new Set(["verified_metadata", "manual_review"]);

export function isTrustedBrandSource(value: string) {
  return trustedBrandSources.has(value);
}

export function isProductMetadataBrandConflictError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("CHECK constraint failed: product_metadata_brand_conflict_guard_check");
}

export function buildProductMetadataBrandConflictGuardStatement(db: D1Database, metadata: ProductMetadata[]) {
  return db.prepare(`INSERT INTO product_metadata_brand_conflict_guard (guard_key, conflict)
  SELECT 'trusted_brand_conflict', 1
  FROM json_each(?1) AS entry
  INNER JOIN product_metadata AS stored
    ON stored.marketplace = json_extract(entry.value, '$.marketplace')
    AND stored.asin = json_extract(entry.value, '$.asin')
  WHERE json_extract(entry.value, '$.brandSource') IN ('verified_metadata', 'manual_review')
    AND stored.brand_source IN ('verified_metadata', 'manual_review')
    AND (stored.normalized_brand_key IS NULL
      OR TRIM(stored.normalized_brand_key) = ''
      OR stored.normalized_brand_key <> json_extract(entry.value, '$.normalizedBrandKey'))
  LIMIT 1`).bind(JSON.stringify(metadata));
}

export function buildProductMetadataUpsertStatement(db: D1Database, metadata: ProductMetadata) {
  return db.prepare(`INSERT INTO product_metadata (
    marketplace, asin, product_type, classification_confidence, classification_rule_id,
    classification_rule_version, classification_evidence_json, raw_brand, normalized_brand,
    normalized_brand_key, brand_alias_rule_id, brand_source, first_seen_market_date, last_seen_market_date
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(marketplace, asin) DO UPDATE SET
    product_type = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.product_type
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.product_type
      ELSE product_metadata.product_type
    END,
    classification_confidence = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_confidence
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_confidence
      ELSE product_metadata.classification_confidence
    END,
    classification_rule_id = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_rule_id
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_rule_id
      ELSE product_metadata.classification_rule_id
    END,
    classification_rule_version = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_rule_version
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_rule_version
      ELSE product_metadata.classification_rule_version
    END,
    classification_evidence_json = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_evidence_json
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_evidence_json
      ELSE product_metadata.classification_evidence_json
    END,
    raw_brand = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.raw_brand ELSE product_metadata.raw_brand END,
    normalized_brand = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.normalized_brand ELSE product_metadata.normalized_brand END,
    normalized_brand_key = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.normalized_brand_key ELSE product_metadata.normalized_brand_key END,
    brand_alias_rule_id = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.brand_alias_rule_id ELSE product_metadata.brand_alias_rule_id END,
    brand_source = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.brand_source ELSE product_metadata.brand_source END,
    first_seen_market_date = MIN(product_metadata.first_seen_market_date, excluded.first_seen_market_date),
    last_seen_market_date = MAX(product_metadata.last_seen_market_date, excluded.last_seen_market_date)`).bind(
    metadata.marketplace,
    metadata.asin,
    metadata.productType,
    metadata.classificationConfidence,
    metadata.classificationRuleId,
    metadata.classificationRuleVersion,
    JSON.stringify(metadata.classificationEvidence),
    metadata.rawBrand,
    metadata.normalizedBrand,
    metadata.normalizedBrandKey,
    metadata.brandAliasRuleId,
    metadata.brandSource,
    metadata.firstSeenMarketDate,
    metadata.lastSeenMarketDate,
  );
}

export function buildProductMetadataBulkUpsertStatement(db: D1Database, metadata: ProductMetadata[]) {
  return db.prepare(`WITH incoming AS (
    SELECT
      json_extract(entry.value, '$.marketplace') AS marketplace,
      json_extract(entry.value, '$.asin') AS asin,
      json_extract(entry.value, '$.productType') AS product_type,
      json_extract(entry.value, '$.classificationConfidence') AS classification_confidence,
      json_extract(entry.value, '$.classificationRuleId') AS classification_rule_id,
      json_extract(entry.value, '$.classificationRuleVersion') AS classification_rule_version,
      json_extract(entry.value, '$.classificationEvidence') AS classification_evidence_json,
      json_extract(entry.value, '$.rawBrand') AS raw_brand,
      json_extract(entry.value, '$.normalizedBrand') AS normalized_brand,
      json_extract(entry.value, '$.normalizedBrandKey') AS normalized_brand_key,
      json_extract(entry.value, '$.brandAliasRuleId') AS brand_alias_rule_id,
      json_extract(entry.value, '$.brandSource') AS brand_source,
      json_extract(entry.value, '$.firstSeenMarketDate') AS first_seen_market_date,
      json_extract(entry.value, '$.lastSeenMarketDate') AS last_seen_market_date
    FROM json_each(?1) AS entry
  )
  INSERT INTO product_metadata (
    marketplace, asin, product_type, classification_confidence, classification_rule_id,
    classification_rule_version, classification_evidence_json, raw_brand, normalized_brand,
    normalized_brand_key, brand_alias_rule_id, brand_source, first_seen_market_date, last_seen_market_date
  ) SELECT
    marketplace, asin, product_type, classification_confidence, classification_rule_id,
    classification_rule_version, classification_evidence_json, raw_brand, normalized_brand,
    normalized_brand_key, brand_alias_rule_id, brand_source, first_seen_market_date, last_seen_market_date
  FROM incoming
  WHERE NOT EXISTS (
    SELECT 1
    FROM incoming AS candidate
    INNER JOIN product_metadata AS stored
      ON stored.marketplace = candidate.marketplace AND stored.asin = candidate.asin
    WHERE candidate.brand_source IN ('verified_metadata', 'manual_review')
      AND stored.brand_source IN ('verified_metadata', 'manual_review')
      AND (stored.normalized_brand_key IS NULL
        OR TRIM(stored.normalized_brand_key) = ''
        OR stored.normalized_brand_key <> candidate.normalized_brand_key)
  )
  ON CONFLICT(marketplace, asin) DO UPDATE SET
    product_type = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.product_type
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.product_type
      ELSE product_metadata.product_type
    END,
    classification_confidence = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_confidence
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_confidence
      ELSE product_metadata.classification_confidence
    END,
    classification_rule_id = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_rule_id
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_rule_id
      ELSE product_metadata.classification_rule_id
    END,
    classification_rule_version = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_rule_version
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_rule_version
      ELSE product_metadata.classification_rule_version
    END,
    classification_evidence_json = CASE
      WHEN excluded.classification_confidence = 'high' AND (product_metadata.classification_confidence <> 'high' OR excluded.classification_rule_version > product_metadata.classification_rule_version) THEN excluded.classification_evidence_json
      WHEN excluded.classification_confidence = 'medium' AND (product_metadata.classification_confidence = 'low' OR (product_metadata.classification_confidence = 'medium' AND excluded.classification_rule_version > product_metadata.classification_rule_version)) THEN excluded.classification_evidence_json
      ELSE product_metadata.classification_evidence_json
    END,
    raw_brand = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.raw_brand ELSE product_metadata.raw_brand END,
    normalized_brand = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.normalized_brand ELSE product_metadata.normalized_brand END,
    normalized_brand_key = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.normalized_brand_key ELSE product_metadata.normalized_brand_key END,
    brand_alias_rule_id = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.brand_alias_rule_id ELSE product_metadata.brand_alias_rule_id END,
    brand_source = CASE WHEN excluded.brand_source IN ('verified_metadata', 'manual_review') THEN excluded.brand_source ELSE product_metadata.brand_source END,
    first_seen_market_date = MIN(product_metadata.first_seen_market_date, excluded.first_seen_market_date),
    last_seen_market_date = MAX(product_metadata.last_seen_market_date, excluded.last_seen_market_date)`).bind(JSON.stringify(metadata));
}
