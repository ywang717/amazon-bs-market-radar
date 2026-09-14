BEGIN;
SET search_path TO amazon_intelligence, public;

ALTER TABLE best_sellers_observation
    ADD COLUMN has_discount boolean,
    ADD COLUMN discounts jsonb NOT NULL DEFAULT '[]'::jsonb,
    ADD CONSTRAINT ck_best_sellers_observation_discounts_array
        CHECK (jsonb_typeof(discounts) = 'array');

CREATE OR REPLACE FUNCTION ingest_best_sellers_snapshot(p_payload jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id bigint;
    v_market_date date := (p_payload->>'market_date')::date;
    v_observed_at timestamptz := (p_payload->>'observed_at')::timestamptz;
    v_target_count integer := (p_payload->>'target_count')::integer;
    v_source jsonb;
    v_item jsonb;
    v_category_key text;
    v_items jsonb;
    v_item_count integer;
    v_unique_asin_count integer;
    v_unique_rank_count integer;
    v_has_discount boolean;
    v_discounts jsonb;
    discount jsonb;
BEGIN
    IF p_payload->>'schema_version' <> 'amazon-best-sellers-snapshot-v1' THEN
        RAISE EXCEPTION 'Unsupported Best Sellers schema version';
    END IF;
    IF jsonb_array_length(COALESCE(p_payload->'source_definitions', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Best Sellers source_definitions is empty';
    END IF;

    INSERT INTO best_sellers_run (
        market_date, observed_at, artifact_path, artifact_sha256, target_count, source_count
    ) VALUES (
        v_market_date, v_observed_at, p_payload->>'artifact_path', p_payload->>'artifact_sha256',
        v_target_count, jsonb_array_length(p_payload->'source_definitions')
    )
    ON CONFLICT (artifact_sha256) DO UPDATE SET artifact_path = EXCLUDED.artifact_path
    RETURNING best_sellers_run_id INTO v_run_id;

    FOR v_source IN SELECT value FROM jsonb_array_elements(p_payload->'source_definitions')
    LOOP
        v_category_key := v_source->>'category_key';
        v_items := COALESCE(p_payload->v_category_key, '[]'::jsonb);
        v_item_count := jsonb_array_length(v_items);
        SELECT count(DISTINCT value->>'asin'), count(DISTINCT (value->>'rank')::integer)
        INTO v_unique_asin_count, v_unique_rank_count
        FROM jsonb_array_elements(v_items);

        INSERT INTO best_sellers_source_run (
            best_sellers_run_id, category_key, category_slug, amazon_node_id, source_url,
            target_count, item_count, unique_asin_count, unique_rank_count, quality_passed
        ) VALUES (
            v_run_id, v_category_key, v_source->>'category_slug', v_source->>'amazon_node_id',
            v_source->>'url', v_target_count, v_item_count, v_unique_asin_count, v_unique_rank_count,
            v_item_count = v_target_count AND v_unique_asin_count = v_target_count AND v_unique_rank_count = v_target_count
        ) ON CONFLICT (best_sellers_run_id, category_key) DO NOTHING;

        FOR v_item IN SELECT value FROM jsonb_array_elements(v_items)
        LOOP
            IF v_item ? 'discounts' AND jsonb_typeof(v_item->'discounts') <> 'array' THEN
                RAISE EXCEPTION 'Best Sellers discounts must be an array';
            END IF;

            v_has_discount := NULLIF(v_item->>'has_discount', '')::boolean;
            v_discounts := COALESCE(v_item->'discounts', '[]'::jsonb);

            FOR discount IN SELECT value FROM jsonb_array_elements(v_discounts)
            LOOP
                IF jsonb_typeof(discount) <> 'object'
                   OR COALESCE(discount->>'kind', '') NOT IN ('COUPON', 'PRICE_DROP', 'PRIME_EXCLUSIVE')
                   OR btrim(COALESCE(discount->>'amount', '')) = '' THEN
                    RAISE EXCEPTION 'Best Sellers discount entries require a supported kind and non-empty amount';
                END IF;
            END LOOP;

            IF v_has_discount IS TRUE AND jsonb_array_length(v_discounts) = 0 THEN
                RAISE EXCEPTION 'Best Sellers has_discount=true requires a non-empty discounts array';
            END IF;
            IF v_has_discount IS NOT TRUE AND jsonb_array_length(v_discounts) <> 0 THEN
                RAISE EXCEPTION 'Best Sellers has_discount=false or null requires an empty discounts array';
            END IF;

            INSERT INTO best_sellers_observation (
                best_sellers_run_id, category_key, market_date, observed_at, asin, rank, title,
                source_url, price_text, price_amount, rating, review_count, source_page,
                has_discount, discounts, payload_json
            ) VALUES (
                v_run_id, v_category_key, v_market_date, v_observed_at, upper(v_item->>'asin'),
                (v_item->>'rank')::integer, v_item->>'title', v_item->>'url', v_item->>'price',
                NULLIF(regexp_replace(COALESCE(v_item->>'price', ''), '[^0-9.]', '', 'g'), '')::numeric,
                NULLIF(v_item->>'rating', '')::numeric, NULLIF(v_item->>'reviews', '')::bigint,
                NULLIF(v_item->>'source_page', '')::integer, v_has_discount,
                v_discounts, v_item
            ) ON CONFLICT (best_sellers_run_id, category_key, asin) DO NOTHING;
        END LOOP;
    END LOOP;
    RETURN v_run_id;
END;
$$;

CREATE OR REPLACE VIEW best_sellers_daily_current AS
WITH latest_source AS (
    SELECT sr.*,
           row_number() OVER (
               PARTITION BY r.market_date, sr.category_key
               ORDER BY r.observed_at DESC, r.best_sellers_run_id DESC
           ) AS version_rank
    FROM best_sellers_source_run sr
    JOIN best_sellers_run r USING (best_sellers_run_id)
)
SELECT
    o.market_date, o.observed_at, o.category_key, ls.category_slug, ls.amazon_node_id,
    ls.quality_passed, ls.item_count, o.asin, o.rank, o.title, o.source_url,
    o.price_text, o.price_amount, o.rating, o.review_count, o.source_page,
    o.has_discount, o.discounts
FROM latest_source ls
JOIN best_sellers_observation o
  ON o.best_sellers_run_id = ls.best_sellers_run_id AND o.category_key = ls.category_key
WHERE ls.version_rank = 1;

DROP VIEW best_sellers_daily_change;

CREATE OR REPLACE VIEW best_sellers_daily_change AS
WITH transitions AS (
    SELECT
        c.*,
        lag(c.rank) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) AS previous_rank,
        lag(c.rank) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) - c.rank AS rank_change,
        lag(c.market_date) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) AS previous_seen_date,
        lag(c.has_discount) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) AS previous_has_discount,
        lag(c.discounts) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) AS previous_discounts
    FROM best_sellers_daily_current c
)
SELECT
    t.*,
    CASE
        WHEN t.previous_seen_date IS NULL
          OR t.previous_has_discount IS NULL
          OR t.has_discount IS NULL THEN 'UNKNOWN'
        WHEN t.previous_has_discount IS FALSE AND t.has_discount IS TRUE THEN 'DISCOUNT_ADDED'
        WHEN t.previous_has_discount IS TRUE AND t.has_discount IS FALSE THEN 'DISCOUNT_REMOVED'
        WHEN t.previous_has_discount IS TRUE AND t.has_discount IS TRUE
          AND t.previous_discounts IS DISTINCT FROM t.discounts THEN 'DISCOUNT_AMOUNT_CHANGED'
        ELSE 'UNCHANGED'
    END AS discount_transition_kind
FROM transitions t;

COMMIT;
