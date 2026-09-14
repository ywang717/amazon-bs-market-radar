BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE best_sellers_market_structure_run (
    market_structure_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    market_date date NOT NULL,
    generated_at timestamptz NOT NULL,
    model_version varchar(80) NOT NULL,
    source_artifact_path varchar(2000) NOT NULL,
    source_artifact_sha256 char(64) NOT NULL UNIQUE,
    payload_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE best_sellers_price_band_metric (
    market_structure_run_id bigint NOT NULL REFERENCES best_sellers_market_structure_run(market_structure_run_id),
    category_key varchar(100) NOT NULL,
    price_band varchar(40) NOT NULL,
    item_count integer NOT NULL CHECK (item_count >= 0),
    share_of_priced_percent numeric(5,2) NOT NULL CHECK (share_of_priced_percent BETWEEN 0 AND 100),
    top_10_count integer NOT NULL CHECK (top_10_count >= 0),
    average_rank numeric(6,2),
    average_price numeric(12,2),
    average_rating numeric(4,2),
    median_reviews numeric(14,2),
    PRIMARY KEY (market_structure_run_id, category_key, price_band)
);

CREATE TABLE best_sellers_accessory_classification (
    market_structure_run_id bigint NOT NULL REFERENCES best_sellers_market_structure_run(market_structure_run_id),
    asin char(10) NOT NULL CHECK (asin ~ '^[A-Z0-9]{10}$'),
    rank integer NOT NULL CHECK (rank BETWEEN 1 AND 100),
    title text NOT NULL,
    primary_type varchar(60) NOT NULL,
    matched_types jsonb NOT NULL,
    classification_basis varchar(40) NOT NULL,
    PRIMARY KEY (market_structure_run_id, asin)
);

CREATE FUNCTION ingest_best_sellers_market_structure(p_payload jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id bigint;
    v_category jsonb;
    v_band jsonb;
    v_product jsonb;
BEGIN
    IF p_payload->>'schema_version' <> 'best-sellers-market-structure-v1' THEN
        RAISE EXCEPTION 'Unsupported market structure schema version';
    END IF;
    INSERT INTO best_sellers_market_structure_run (
        market_date, generated_at, model_version, source_artifact_path,
        source_artifact_sha256, payload_json
    ) VALUES (
        (p_payload->>'market_date')::date, (p_payload->>'generated_at')::timestamptz,
        p_payload->>'model_version', p_payload->>'source_artifact_path',
        p_payload->>'source_artifact_sha256', p_payload
    )
    ON CONFLICT (source_artifact_sha256)
    DO UPDATE SET source_artifact_path = EXCLUDED.source_artifact_path
    RETURNING market_structure_run_id INTO v_run_id;

    FOR v_category IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'categories', '[]'::jsonb))
    LOOP
        FOR v_band IN SELECT value FROM jsonb_array_elements(COALESCE(v_category->'price_bands', '[]'::jsonb))
        LOOP
            INSERT INTO best_sellers_price_band_metric (
                market_structure_run_id, category_key, price_band, item_count,
                share_of_priced_percent, top_10_count, average_rank, average_price,
                average_rating, median_reviews
            ) VALUES (
                v_run_id, v_category->>'category', v_band->>'price_band',
                (v_band->>'item_count')::integer, (v_band->>'share_of_priced_percent')::numeric,
                (v_band->>'top_10_count')::integer, NULLIF(v_band->>'average_rank', '')::numeric,
                NULLIF(v_band->>'average_price', '')::numeric,
                NULLIF(v_band->>'average_rating', '')::numeric,
                NULLIF(v_band->>'median_reviews', '')::numeric
            ) ON CONFLICT (market_structure_run_id, category_key, price_band) DO NOTHING;
        END LOOP;
    END LOOP;

    FOR v_product IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'accessory_analysis'->'products', '[]'::jsonb))
    LOOP
        INSERT INTO best_sellers_accessory_classification (
            market_structure_run_id, asin, rank, title, primary_type, matched_types, classification_basis
        ) VALUES (
            v_run_id, upper(v_product->>'asin'), (v_product->>'rank')::integer,
            v_product->>'title', v_product->>'primary_type',
            COALESCE(v_product->'matched_types', '[]'::jsonb), v_product->>'classification_basis'
        ) ON CONFLICT (market_structure_run_id, asin) DO NOTHING;
    END LOOP;
    RETURN v_run_id;
END;
$$;

CREATE VIEW best_sellers_price_band_latest AS
WITH latest_run AS (
    SELECT *, row_number() OVER (PARTITION BY market_date ORDER BY generated_at DESC, market_structure_run_id DESC) AS version_rank
    FROM best_sellers_market_structure_run
)
SELECT r.market_date, r.generated_at, r.model_version, m.*
FROM latest_run r
JOIN best_sellers_price_band_metric m USING (market_structure_run_id)
WHERE r.version_rank = 1;

CREATE VIEW best_sellers_accessory_classification_latest AS
WITH latest_run AS (
    SELECT *, row_number() OVER (PARTITION BY market_date ORDER BY generated_at DESC, market_structure_run_id DESC) AS version_rank
    FROM best_sellers_market_structure_run
)
SELECT r.market_date, r.generated_at, r.model_version, a.*
FROM latest_run r
JOIN best_sellers_accessory_classification a USING (market_structure_run_id)
WHERE r.version_rank = 1;

COMMIT;
