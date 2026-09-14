BEGIN;
SET search_path TO amazon_intelligence, public;

-- Keep migration 013's duplicate and trusted-brand conflict guards while
-- restoring the version-aware classification replacement from migration 012.
CREATE OR REPLACE FUNCTION upsert_best_sellers_product_metadata(p_rows jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_upserted_count bigint;
    v_identity record;
    v_conflict record;
BEGIN
    IF jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'Best Sellers product metadata must be a JSON array';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(p_rows) AS r(marketplace_code varchar(32), asin varchar(10))
        GROUP BY r.marketplace_code, upper(r.asin)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Best Sellers product metadata contains duplicate marketplace/ASIN rows';
    END IF;

    FOR v_identity IN
        SELECT DISTINCT r.marketplace_code, upper(r.asin) AS asin
        FROM jsonb_to_recordset(p_rows) AS r(marketplace_code varchar(32), asin varchar(10))
        ORDER BY r.marketplace_code, upper(r.asin)
    LOOP
        PERFORM pg_advisory_xact_lock(hashtextextended(v_identity.marketplace_code || '/' || v_identity.asin, 0));
    END LOOP;

    SELECT existing.marketplace_code, existing.asin
    INTO v_conflict
    FROM best_sellers_product_metadata existing
    JOIN jsonb_to_recordset(p_rows) AS incoming(
        marketplace_code varchar(32),
        asin varchar(10),
        normalized_brand_key varchar(300),
        brand_source varchar(32)
    )
      ON incoming.marketplace_code = existing.marketplace_code
     AND upper(incoming.asin) = existing.asin
    WHERE existing.brand_source IN ('verified_metadata', 'manual_review')
      AND incoming.brand_source IN ('verified_metadata', 'manual_review')
      AND existing.normalized_brand_key IS DISTINCT FROM incoming.normalized_brand_key
    ORDER BY existing.marketplace_code, existing.asin
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Best Sellers product metadata trusted brand conflict for %/%', v_conflict.marketplace_code, v_conflict.asin;
    END IF;

    INSERT INTO best_sellers_product_metadata (
        marketplace_code,
        asin,
        product_type,
        classification_confidence,
        classification_rule_id,
        classification_rule_version,
        classification_evidence,
        raw_brand,
        normalized_brand,
        normalized_brand_key,
        brand_alias_rule_id,
        brand_source,
        first_seen_market_date,
        last_seen_market_date
    )
    SELECT
        r.marketplace_code,
        upper(r.asin),
        r.product_type,
        r.classification_confidence,
        r.classification_rule_id,
        r.classification_rule_version,
        r.classification_evidence,
        r.raw_brand,
        r.normalized_brand,
        r.normalized_brand_key,
        r.brand_alias_rule_id,
        r.brand_source,
        r.first_seen_market_date,
        r.last_seen_market_date
    FROM jsonb_to_recordset(p_rows) AS r(
        marketplace_code varchar(32),
        asin varchar(10),
        product_type varchar(64),
        classification_confidence varchar(16),
        classification_rule_id varchar(120),
        classification_rule_version varchar(80),
        classification_evidence jsonb,
        raw_brand varchar(300),
        normalized_brand varchar(300),
        normalized_brand_key varchar(300),
        brand_alias_rule_id varchar(120),
        brand_source varchar(32),
        first_seen_market_date date,
        last_seen_market_date date
    )
    ON CONFLICT (marketplace_code, asin) DO UPDATE
    SET
        product_type = CASE
            WHEN EXCLUDED.classification_confidence = 'high'
              AND (best_sellers_product_metadata.classification_confidence <> 'high'
                OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)
              THEN EXCLUDED.product_type
            WHEN EXCLUDED.classification_confidence = 'medium'
              AND (best_sellers_product_metadata.classification_confidence = 'low'
                OR (best_sellers_product_metadata.classification_confidence = 'medium'
                  AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version))
              THEN EXCLUDED.product_type
            ELSE best_sellers_product_metadata.product_type
        END,
        classification_confidence = CASE
            WHEN EXCLUDED.classification_confidence = 'high'
              AND (best_sellers_product_metadata.classification_confidence <> 'high'
                OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)
              THEN EXCLUDED.classification_confidence
            WHEN EXCLUDED.classification_confidence = 'medium'
              AND (best_sellers_product_metadata.classification_confidence = 'low'
                OR (best_sellers_product_metadata.classification_confidence = 'medium'
                  AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version))
              THEN EXCLUDED.classification_confidence
            ELSE best_sellers_product_metadata.classification_confidence
        END,
        classification_rule_id = CASE
            WHEN EXCLUDED.classification_confidence = 'high'
              AND (best_sellers_product_metadata.classification_confidence <> 'high'
                OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)
              THEN EXCLUDED.classification_rule_id
            WHEN EXCLUDED.classification_confidence = 'medium'
              AND (best_sellers_product_metadata.classification_confidence = 'low'
                OR (best_sellers_product_metadata.classification_confidence = 'medium'
                  AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version))
              THEN EXCLUDED.classification_rule_id
            ELSE best_sellers_product_metadata.classification_rule_id
        END,
        classification_rule_version = CASE
            WHEN EXCLUDED.classification_confidence = 'high'
              AND (best_sellers_product_metadata.classification_confidence <> 'high'
                OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)
              THEN EXCLUDED.classification_rule_version
            WHEN EXCLUDED.classification_confidence = 'medium'
              AND (best_sellers_product_metadata.classification_confidence = 'low'
                OR (best_sellers_product_metadata.classification_confidence = 'medium'
                  AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version))
              THEN EXCLUDED.classification_rule_version
            ELSE best_sellers_product_metadata.classification_rule_version
        END,
        classification_evidence = CASE
            WHEN EXCLUDED.classification_confidence = 'high'
              AND (best_sellers_product_metadata.classification_confidence <> 'high'
                OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)
              THEN EXCLUDED.classification_evidence
            WHEN EXCLUDED.classification_confidence = 'medium'
              AND (best_sellers_product_metadata.classification_confidence = 'low'
                OR (best_sellers_product_metadata.classification_confidence = 'medium'
                  AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version))
              THEN EXCLUDED.classification_evidence
            ELSE best_sellers_product_metadata.classification_evidence
        END,
        raw_brand = CASE WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.raw_brand ELSE best_sellers_product_metadata.raw_brand END,
        normalized_brand = CASE WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.normalized_brand ELSE best_sellers_product_metadata.normalized_brand END,
        normalized_brand_key = CASE WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.normalized_brand_key ELSE best_sellers_product_metadata.normalized_brand_key END,
        brand_alias_rule_id = CASE WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.brand_alias_rule_id ELSE best_sellers_product_metadata.brand_alias_rule_id END,
        brand_source = CASE WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.brand_source ELSE best_sellers_product_metadata.brand_source END,
        first_seen_market_date = LEAST(best_sellers_product_metadata.first_seen_market_date, EXCLUDED.first_seen_market_date),
        last_seen_market_date = GREATEST(best_sellers_product_metadata.last_seen_market_date, EXCLUDED.last_seen_market_date),
        updated_at = now();

    GET DIAGNOSTICS v_upserted_count = ROW_COUNT;
    RETURN v_upserted_count;
END;
$$;

COMMIT;
