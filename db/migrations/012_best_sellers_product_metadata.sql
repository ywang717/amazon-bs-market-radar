BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE best_sellers_product_metadata (
    marketplace_code varchar(32) NOT NULL,
    asin char(10) NOT NULL CHECK (asin ~ '^[A-Z0-9]{10}$'),
    product_type varchar(64) NOT NULL CHECK (product_type IN (
        'electric_pressure_washer',
        'gas_pressure_washer',
        'cordless_pressure_washer',
        'surface_cleaner',
        'pressure_washer_gun',
        'hose',
        'nozzle',
        'chemical_cleaner',
        'pump_protector',
        'other_accessory',
        'unknown'
    )),
    classification_confidence varchar(16) NOT NULL CHECK (classification_confidence IN ('high', 'medium', 'low')),
    classification_rule_id varchar(120),
    classification_rule_version varchar(80) NOT NULL,
    classification_evidence jsonb NOT NULL CHECK (jsonb_typeof(classification_evidence) = 'array' AND jsonb_array_length(classification_evidence) > 0),
    raw_brand varchar(300),
    normalized_brand varchar(300),
    normalized_brand_key varchar(300),
    brand_alias_rule_id varchar(120),
    brand_source varchar(32) NOT NULL CHECK (brand_source IN ('verified_metadata', 'manual_review', 'unknown')),
    first_seen_market_date date NOT NULL,
    last_seen_market_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (marketplace_code, asin),
    CHECK (first_seen_market_date <= last_seen_market_date),
    CHECK (
        (product_type = 'unknown' AND classification_confidence = 'low' AND classification_rule_id IS NULL)
        OR (
            product_type <> 'unknown'
            AND classification_confidence IN ('medium', 'high')
            AND classification_rule_id IS NOT NULL
            AND btrim(classification_rule_id) <> ''
        )
    ),
    CHECK ((brand_source = 'unknown' AND raw_brand IS NULL AND normalized_brand IS NULL AND normalized_brand_key IS NULL AND brand_alias_rule_id IS NULL)
        OR (brand_source <> 'unknown' AND raw_brand IS NOT NULL AND normalized_brand IS NOT NULL AND normalized_brand_key IS NOT NULL))
);

CREATE VIEW best_sellers_valid_category_day AS
WITH latest_source AS (
    SELECT
        r.best_sellers_run_id,
        r.market_date,
        r.observed_at,
        sr.category_key,
        sr.category_slug,
        sr.amazon_node_id,
        sr.quality_passed,
        row_number() OVER (
            PARTITION BY r.market_date, sr.category_key
            ORDER BY r.observed_at DESC, r.best_sellers_run_id DESC
        ) AS version_rank
    FROM best_sellers_source_run sr
    JOIN best_sellers_run r USING (best_sellers_run_id)
)
SELECT
    ls.market_date,
    ls.observed_at,
    ls.category_key,
    ls.category_slug,
    ls.amazon_node_id,
    ls.best_sellers_run_id
FROM latest_source ls
JOIN best_sellers_observation o
  ON o.best_sellers_run_id = ls.best_sellers_run_id
 AND o.category_key = ls.category_key
WHERE ls.version_rank = 1
  AND ls.quality_passed
GROUP BY
    ls.market_date,
    ls.observed_at,
    ls.category_key,
    ls.category_slug,
    ls.amazon_node_id,
    ls.best_sellers_run_id
HAVING count(*) = 30
   AND count(DISTINCT o.rank) = 30
   AND count(DISTINCT o.asin) = 30
   AND min(o.rank) = 1
   AND max(o.rank) = 30;

CREATE FUNCTION upsert_best_sellers_product_metadata(p_rows jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_upserted_count bigint;
BEGIN
    IF jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'Best Sellers product metadata must be a JSON array';
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
            WHEN EXCLUDED.classification_confidence = 'high' AND (best_sellers_product_metadata.classification_confidence <> 'high' OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version) THEN EXCLUDED.product_type
            WHEN EXCLUDED.classification_confidence = 'medium' AND (best_sellers_product_metadata.classification_confidence = 'low' OR (best_sellers_product_metadata.classification_confidence = 'medium' AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)) THEN EXCLUDED.product_type
            ELSE best_sellers_product_metadata.product_type
        END,
        classification_confidence = CASE
            WHEN EXCLUDED.classification_confidence = 'high' AND (best_sellers_product_metadata.classification_confidence <> 'high' OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version) THEN EXCLUDED.classification_confidence
            WHEN EXCLUDED.classification_confidence = 'medium' AND (best_sellers_product_metadata.classification_confidence = 'low' OR (best_sellers_product_metadata.classification_confidence = 'medium' AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)) THEN EXCLUDED.classification_confidence
            ELSE best_sellers_product_metadata.classification_confidence
        END,
        classification_rule_id = CASE
            WHEN EXCLUDED.classification_confidence = 'high' AND (best_sellers_product_metadata.classification_confidence <> 'high' OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version) THEN EXCLUDED.classification_rule_id
            WHEN EXCLUDED.classification_confidence = 'medium' AND (best_sellers_product_metadata.classification_confidence = 'low' OR (best_sellers_product_metadata.classification_confidence = 'medium' AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)) THEN EXCLUDED.classification_rule_id
            ELSE best_sellers_product_metadata.classification_rule_id
        END,
        classification_rule_version = CASE
            WHEN EXCLUDED.classification_confidence = 'high' AND (best_sellers_product_metadata.classification_confidence <> 'high' OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version) THEN EXCLUDED.classification_rule_version
            WHEN EXCLUDED.classification_confidence = 'medium' AND (best_sellers_product_metadata.classification_confidence = 'low' OR (best_sellers_product_metadata.classification_confidence = 'medium' AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)) THEN EXCLUDED.classification_rule_version
            ELSE best_sellers_product_metadata.classification_rule_version
        END,
        classification_evidence = CASE
            WHEN EXCLUDED.classification_confidence = 'high' AND (best_sellers_product_metadata.classification_confidence <> 'high' OR EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version) THEN EXCLUDED.classification_evidence
            WHEN EXCLUDED.classification_confidence = 'medium' AND (best_sellers_product_metadata.classification_confidence = 'low' OR (best_sellers_product_metadata.classification_confidence = 'medium' AND EXCLUDED.classification_rule_version > best_sellers_product_metadata.classification_rule_version)) THEN EXCLUDED.classification_evidence
            ELSE best_sellers_product_metadata.classification_evidence
        END,
        raw_brand = CASE
            WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.raw_brand
            ELSE best_sellers_product_metadata.raw_brand
        END,
        normalized_brand = CASE
            WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.normalized_brand
            ELSE best_sellers_product_metadata.normalized_brand
        END,
        normalized_brand_key = CASE
            WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.normalized_brand_key
            ELSE best_sellers_product_metadata.normalized_brand_key
        END,
        brand_alias_rule_id = CASE
            WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.brand_alias_rule_id
            ELSE best_sellers_product_metadata.brand_alias_rule_id
        END,
        brand_source = CASE
            WHEN EXCLUDED.brand_source IN ('verified_metadata', 'manual_review') THEN EXCLUDED.brand_source
            ELSE best_sellers_product_metadata.brand_source
        END,
        first_seen_market_date = LEAST(best_sellers_product_metadata.first_seen_market_date, EXCLUDED.first_seen_market_date),
        last_seen_market_date = GREATEST(best_sellers_product_metadata.last_seen_market_date, EXCLUDED.last_seen_market_date),
        updated_at = now();

    GET DIAGNOSTICS v_upserted_count = ROW_COUNT;
    RETURN v_upserted_count;
END;
$$;

COMMIT;
