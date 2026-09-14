BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE FUNCTION start_collection_run(
    p_run_id uuid,
    p_source_id uuid,
    p_started_at timestamptz,
    p_parser_version varchar,
    p_expected_count integer
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO collection_run (
        run_id, source_id, started_at, status, parser_version, expected_count
    ) VALUES (
        p_run_id, p_source_id, p_started_at, 'RUNNING', p_parser_version, p_expected_count
    ) ON CONFLICT (run_id) DO NOTHING;
END;
$$;

CREATE FUNCTION ingest_canonical_observation(p_record jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_marketplace_id bigint;
    v_category_id bigint;
    v_brand_id bigint;
    v_seller_id bigint;
    v_product_id bigint;
    v_source_id uuid := (p_record->>'source_id')::uuid;
    v_run_id uuid := (p_record->>'run_id')::uuid;
    v_observed_at timestamptz := (p_record->>'observed_at')::timestamptz;
    v_market_date date := (p_record->>'market_date')::date;
    v_record_key char(64) := p_record->>'record_key';
    v_brand_key text;
    v_seller_key text;
BEGIN
    IF p_record->>'schema_version' <> 'canonical-observation-v1' THEN
        RAISE EXCEPTION 'Unsupported observation schema version';
    END IF;

    SELECT marketplace_id INTO STRICT v_marketplace_id
    FROM marketplace WHERE code = p_record->>'marketplace';

    SELECT category_id INTO STRICT v_category_id
    FROM category WHERE slug = p_record->>'category_slug' AND active = true;

    PERFORM 1 FROM source_definition
    WHERE source_id = v_source_id
      AND marketplace_id = v_marketplace_id
      AND category_id = v_category_id
      AND active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source definition is missing, inactive, or mismatched: %', v_source_id;
    END IF;

    PERFORM 1 FROM collection_run WHERE run_id = v_run_id AND source_id = v_source_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Collection run must be started before ingestion: %', v_run_id;
    END IF;

    IF NULLIF(btrim(p_record->>'brand_raw'), '') IS NOT NULL THEN
        v_brand_key := lower(regexp_replace(btrim(p_record->>'brand_raw'), '[^[:alnum:]]+', '', 'g'));
        INSERT INTO brand (canonical_name, normalized_key)
        VALUES (btrim(p_record->>'brand_raw'), v_brand_key)
        ON CONFLICT (normalized_key) DO UPDATE SET canonical_name = brand.canonical_name
        RETURNING brand_id INTO v_brand_id;
    END IF;

    IF NULLIF(btrim(p_record->>'seller_raw'), '') IS NOT NULL THEN
        v_seller_key := lower(regexp_replace(btrim(p_record->>'seller_raw'), '[^[:alnum:]]+', '', 'g'));
        INSERT INTO seller (marketplace_id, display_name, normalized_key)
        VALUES (v_marketplace_id, btrim(p_record->>'seller_raw'), v_seller_key)
        ON CONFLICT (marketplace_id, normalized_key)
        DO UPDATE SET display_name = seller.display_name
        RETURNING seller_id INTO v_seller_id;
    END IF;

    INSERT INTO product (
        marketplace_id, asin, brand_id, model, first_seen_at, last_seen_at
    ) VALUES (
        v_marketplace_id, p_record->>'asin', v_brand_id, NULLIF(p_record->>'model', ''),
        v_observed_at, v_observed_at
    )
    ON CONFLICT (marketplace_id, asin) DO UPDATE SET
        brand_id = COALESCE(EXCLUDED.brand_id, product.brand_id),
        model = COALESCE(EXCLUDED.model, product.model),
        last_seen_at = GREATEST(product.last_seen_at, EXCLUDED.last_seen_at),
        updated_at = now()
    RETURNING product_id INTO v_product_id;

    INSERT INTO product_category (
        product_id, category_id, valid_from, confidence, mapping_method
    ) VALUES (v_product_id, v_category_id, v_market_date, 1.0, 'SOURCE_CONFIGURATION')
    ON CONFLICT (product_id, category_id, valid_from) DO NOTHING;

    INSERT INTO ranking_observation (
        run_id, market_date, observed_at, source_id, category_id, product_id,
        rank, source_url, record_key
    ) VALUES (
        v_run_id, v_market_date, v_observed_at, v_source_id, v_category_id, v_product_id,
        (p_record->>'rank')::integer, p_record->>'url', v_record_key
    ) ON CONFLICT (record_key) DO NOTHING;

    INSERT INTO offer_snapshot (
        run_id, product_id, market_date, observed_at, price, currency, coupon_text,
        seller_id, fba_status, record_key
    ) VALUES (
        v_run_id, v_product_id, v_market_date, v_observed_at,
        NULLIF(p_record->>'price', '')::numeric, p_record->>'currency',
        NULLIF(p_record->>'coupon', ''), v_seller_id,
        COALESCE(NULLIF(p_record->>'fba_status', ''), 'UNKNOWN')::fba_status,
        v_record_key
    ) ON CONFLICT (record_key) DO NOTHING;

    INSERT INTO listing_snapshot (
        run_id, product_id, market_date, observed_at, title, model, rating,
        review_count, first_available_date, canonical_url, content_hash, record_key
    ) VALUES (
        v_run_id, v_product_id, v_market_date, v_observed_at, p_record->>'title',
        NULLIF(p_record->>'model', ''), NULLIF(p_record->>'rating', '')::numeric,
        NULLIF(p_record->>'review_count', '')::integer,
        NULLIF(p_record->>'first_available_date', '')::date,
        p_record->>'url', v_record_key, v_record_key
    ) ON CONFLICT (record_key) DO NOTHING;
END;
$$;

CREATE FUNCTION finish_collection_run(
    p_run_id uuid,
    p_finished_at timestamptz,
    p_status run_status,
    p_raw_count integer,
    p_accepted_count integer,
    p_rejected_count integer,
    p_error_summary text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE collection_run SET
        finished_at = p_finished_at,
        status = p_status,
        raw_count = p_raw_count,
        accepted_count = p_accepted_count,
        rejected_count = p_rejected_count,
        error_summary = p_error_summary
    WHERE run_id = p_run_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown collection run: %', p_run_id; END IF;
END;
$$;

COMMIT;

