\set ON_ERROR_STOP on
SET search_path TO amazon_intelligence, public;

CREATE OR REPLACE FUNCTION pg_temp.discount_payload(
    p_market_date date,
    p_sha text,
    p_asin text,
    p_has_discount boolean,
    p_discounts jsonb
) RETURNS jsonb
LANGUAGE sql
AS $$
    SELECT jsonb_build_object(
        'schema_version', 'amazon-best-sellers-snapshot-v1',
        'market_date', p_market_date,
        'observed_at', (p_market_date::text || 'T06:00:00Z')::timestamptz,
        'artifact_path', '/test/' || p_sha || '.json',
        'artifact_sha256', p_sha,
        'target_count', 1,
        'source_definitions', jsonb_build_array(jsonb_build_object(
            'category_key', 'pressure_washers',
            'category_slug', 'pressure-washers',
            'amazon_node_id', '552856',
            'url', 'https://www.amazon.com/Best-Sellers-Pressure-Washers/zgbs/552856'
        )),
        'pressure_washers', jsonb_build_array(jsonb_build_object(
            'asin', p_asin,
            'rank', 1,
            'title', 'Test item ' || p_asin,
            'url', 'https://www.amazon.com/dp/' || p_asin,
            'price', '$100.00',
            'rating', 4.5,
            'reviews', 100,
            'source_page', 1,
            'has_discount', p_has_discount,
            'discounts', p_discounts
        ))
    );
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_discount_payload_rejected(
    p_payload jsonb,
    p_expected_message text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM ingest_best_sellers_snapshot(p_payload);
        RAISE EXCEPTION 'EXPECTED_REJECTION_NOT_RAISED';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message = 'EXPECTED_REJECTION_NOT_RAISED' THEN
            RAISE EXCEPTION '%', v_message;
        END IF;
        IF position(p_expected_message IN v_message) = 0 THEN
            RAISE EXCEPTION 'Unexpected rejection: %', v_message;
        END IF;
    END;
END;
$$;

BEGIN;

SELECT pg_temp.expect_discount_payload_rejected(
    pg_temp.discount_payload('2026-08-01', repeat('1', 64), 'B0BADTRUE1', true, '[]'::jsonb),
    'has_discount=true requires a non-empty discounts array'
);
SELECT pg_temp.expect_discount_payload_rejected(
    pg_temp.discount_payload('2026-08-01', repeat('7', 64), 'B0BADTRUE2', true, '[]'::jsonb) #- '{pressure_washers,0,discounts}',
    'has_discount=true requires a non-empty discounts array'
);
SELECT pg_temp.expect_discount_payload_rejected(
    pg_temp.discount_payload('2026-08-01', repeat('2', 64), 'B0BADFALS1', false, '[{"kind":"COUPON","amount":"10% off"}]'::jsonb),
    'has_discount=false or null requires an empty discounts array'
);
SELECT pg_temp.expect_discount_payload_rejected(
    pg_temp.discount_payload('2026-08-01', repeat('3', 64), 'B0BADNULL1', null, '[{"kind":"COUPON","amount":"10% off"}]'::jsonb),
    'has_discount=false or null requires an empty discounts array'
);
SELECT pg_temp.expect_discount_payload_rejected(
    pg_temp.discount_payload('2026-08-01', repeat('a', 64), 'B0BADLIST1', true, '[{"kind":"COUPON","amount":""}]'::jsonb),
    'discount entries require a supported kind and non-empty amount'
);

SELECT ingest_best_sellers_snapshot(
    pg_temp.discount_payload('2026-08-02', repeat('4', 64), 'B0GOODTRU1', true, '[{"kind":"COUPON","amount":"10% off"}]'::jsonb)
);
SELECT ingest_best_sellers_snapshot(
    pg_temp.discount_payload('2026-08-03', repeat('5', 64), 'B0GOODFAL1', false, '[]'::jsonb)
);
SELECT ingest_best_sellers_snapshot(
    pg_temp.discount_payload('2026-08-04', repeat('6', 64), 'B0GOODNUL1', null, '[]'::jsonb)
);

DO $$
DECLARE
    v_accepted_count integer;
BEGIN
    SELECT count(*) INTO v_accepted_count
    FROM best_sellers_observation
    WHERE asin IN ('B0GOODTRU1', 'B0GOODFAL1', 'B0GOODNUL1')
      AND (
          (asin = 'B0GOODTRU1' AND has_discount IS TRUE AND jsonb_array_length(discounts) = 1)
          OR (asin = 'B0GOODFAL1' AND has_discount IS FALSE AND discounts = '[]'::jsonb)
          OR (asin = 'B0GOODNUL1' AND has_discount IS NULL AND discounts = '[]'::jsonb)
      );
    IF v_accepted_count <> 3 THEN
        RAISE EXCEPTION 'Expected accepted true/false/null rows, found %', v_accepted_count;
    END IF;
END;
$$;

DO $$
DECLARE
    v_columns text[];
BEGIN
    SELECT array_agg(column_name::text ORDER BY ordinal_position)
    INTO v_columns
    FROM information_schema.columns
    WHERE table_schema = 'amazon_intelligence'
      AND table_name = 'best_sellers_daily_change';

    IF NOT (v_columns @> ARRAY[
        'has_discount',
        'discounts',
        'previous_has_discount',
        'previous_discounts',
        'discount_transition_kind'
    ]) THEN
        RAISE EXCEPTION 'Daily change view is missing reportable discount history columns: %', v_columns;
    END IF;
END;
$$;

DO $$
DECLARE
    v_previous_run bigint;
    v_current_run bigint;
    v_transition_mismatch_count integer;
BEGIN
    INSERT INTO best_sellers_run (
        market_date, observed_at, artifact_path, artifact_sha256, target_count, source_count
    ) VALUES (
        '2026-08-10', '2026-08-10T06:00:00Z', '/test/transitions-previous.json', repeat('8', 64), 5, 1
    ) RETURNING best_sellers_run_id INTO v_previous_run;
    INSERT INTO best_sellers_run (
        market_date, observed_at, artifact_path, artifact_sha256, target_count, source_count
    ) VALUES (
        '2026-08-11', '2026-08-11T06:00:00Z', '/test/transitions-current.json', repeat('9', 64), 5, 1
    ) RETURNING best_sellers_run_id INTO v_current_run;

    INSERT INTO best_sellers_source_run (
        best_sellers_run_id, category_key, category_slug, amazon_node_id, source_url,
        target_count, item_count, unique_asin_count, unique_rank_count, quality_passed
    ) VALUES
        (v_previous_run, 'pressure_washers', 'pressure-washers', '552856', 'https://example.test/chart', 5, 5, 5, 5, true),
        (v_current_run, 'pressure_washers', 'pressure-washers', '552856', 'https://example.test/chart', 5, 5, 5, 5, true);

    INSERT INTO best_sellers_observation (
        best_sellers_run_id, category_key, market_date, observed_at, asin, rank, title,
        source_url, has_discount, discounts, payload_json
    ) VALUES
        (v_previous_run, 'pressure_washers', '2026-08-10', '2026-08-10T06:00:00Z', 'B0ADD00001', 1, 'Added', 'https://example.test/B0ADD00001', false, '[]', '{}'),
        (v_previous_run, 'pressure_washers', '2026-08-10', '2026-08-10T06:00:00Z', 'B0REMOVE01', 2, 'Removed', 'https://example.test/B0REMOVE01', true, '[{"kind":"COUPON","amount":"10% off"}]', '{}'),
        (v_previous_run, 'pressure_washers', '2026-08-10', '2026-08-10T06:00:00Z', 'B0CHANGE01', 3, 'Changed', 'https://example.test/B0CHANGE01', true, '[{"kind":"COUPON","amount":"10% off"}]', '{}'),
        (v_previous_run, 'pressure_washers', '2026-08-10', '2026-08-10T06:00:00Z', 'B0SAME0001', 4, 'Same', 'https://example.test/B0SAME0001', false, '[]', '{}'),
        (v_previous_run, 'pressure_washers', '2026-08-10', '2026-08-10T06:00:00Z', 'B0UNKNOWN1', 5, 'Unknown', 'https://example.test/B0UNKNOWN1', null, '[]', '{}'),
        (v_current_run, 'pressure_washers', '2026-08-11', '2026-08-11T06:00:00Z', 'B0ADD00001', 5, 'Added', 'https://example.test/B0ADD00001', true, '[{"kind":"COUPON","amount":"10% off"}]', '{}'),
        (v_current_run, 'pressure_washers', '2026-08-11', '2026-08-11T06:00:00Z', 'B0REMOVE01', 4, 'Removed', 'https://example.test/B0REMOVE01', false, '[]', '{}'),
        (v_current_run, 'pressure_washers', '2026-08-11', '2026-08-11T06:00:00Z', 'B0CHANGE01', 3, 'Changed', 'https://example.test/B0CHANGE01', true, '[{"kind":"COUPON","amount":"20% off"}]', '{}'),
        (v_current_run, 'pressure_washers', '2026-08-11', '2026-08-11T06:00:00Z', 'B0SAME0001', 2, 'Same', 'https://example.test/B0SAME0001', false, '[]', '{}'),
        (v_current_run, 'pressure_washers', '2026-08-11', '2026-08-11T06:00:00Z', 'B0UNKNOWN1', 1, 'Unknown', 'https://example.test/B0UNKNOWN1', true, '[{"kind":"COUPON","amount":"10% off"}]', '{}');

    WITH expected(asin, transition_kind) AS (
        VALUES
            ('B0ADD00001', 'DISCOUNT_ADDED'),
            ('B0REMOVE01', 'DISCOUNT_REMOVED'),
            ('B0CHANGE01', 'DISCOUNT_AMOUNT_CHANGED'),
            ('B0SAME0001', 'UNCHANGED'),
            ('B0UNKNOWN1', 'UNKNOWN')
    )
    SELECT count(*) INTO v_transition_mismatch_count
    FROM expected e
    LEFT JOIN best_sellers_daily_change c
      ON c.category_key = 'pressure_washers'
     AND c.market_date = '2026-08-11'
     AND c.asin = e.asin
    WHERE c.discount_transition_kind IS DISTINCT FROM e.transition_kind;
    IF v_transition_mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Daily change view did not identify all five transition kinds safely';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM best_sellers_daily_change
        WHERE asin = 'B0ADD00001'
          AND market_date = '2026-08-11'
          AND previous_has_discount IS FALSE
          AND has_discount IS TRUE
          AND previous_discounts = '[]'::jsonb
          AND jsonb_array_length(discounts) = 1
          AND previous_rank = 1
          AND rank = 5
          AND rank_change = -4
    ) THEN
        RAISE EXCEPTION 'Daily change view did not preserve the prior/current discount and rank values';
    END IF;
END;
$$;

ROLLBACK;
