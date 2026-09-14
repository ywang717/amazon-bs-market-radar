BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE best_sellers_run (
    best_sellers_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    market_date date NOT NULL,
    observed_at timestamptz NOT NULL,
    artifact_path varchar(2000) NOT NULL,
    artifact_sha256 char(64) NOT NULL UNIQUE,
    target_count integer NOT NULL CHECK (target_count BETWEEN 1 AND 100),
    source_count integer NOT NULL CHECK (source_count > 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE best_sellers_source_run (
    best_sellers_run_id bigint NOT NULL REFERENCES best_sellers_run(best_sellers_run_id),
    category_key varchar(100) NOT NULL,
    category_slug varchar(160) NOT NULL,
    amazon_node_id varchar(40) NOT NULL,
    source_url varchar(2000) NOT NULL,
    target_count integer NOT NULL CHECK (target_count BETWEEN 1 AND 100),
    item_count integer NOT NULL CHECK (item_count >= 0),
    unique_asin_count integer NOT NULL CHECK (unique_asin_count >= 0),
    unique_rank_count integer NOT NULL CHECK (unique_rank_count >= 0),
    quality_passed boolean NOT NULL,
    PRIMARY KEY (best_sellers_run_id, category_key)
);

CREATE TABLE best_sellers_observation (
    best_sellers_observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    best_sellers_run_id bigint NOT NULL,
    category_key varchar(100) NOT NULL,
    market_date date NOT NULL,
    observed_at timestamptz NOT NULL,
    asin char(10) NOT NULL CHECK (asin ~ '^[A-Z0-9]{10}$'),
    rank integer NOT NULL CHECK (rank BETWEEN 1 AND 100),
    title text NOT NULL,
    source_url varchar(2000) NOT NULL,
    price_text varchar(80),
    price_amount numeric(12,2) CHECK (price_amount IS NULL OR price_amount >= 0),
    rating numeric(3,2) CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
    review_count bigint CHECK (review_count IS NULL OR review_count >= 0),
    source_page integer CHECK (source_page IS NULL OR source_page > 0),
    payload_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (best_sellers_run_id, category_key)
        REFERENCES best_sellers_source_run(best_sellers_run_id, category_key),
    UNIQUE (best_sellers_run_id, category_key, asin),
    UNIQUE (best_sellers_run_id, category_key, rank)
);

CREATE INDEX ix_best_sellers_run_market_date ON best_sellers_run (market_date DESC, observed_at DESC);
CREATE INDEX ix_best_sellers_observation_lookup ON best_sellers_observation (category_key, asin, market_date DESC);
CREATE INDEX ix_best_sellers_observation_rank ON best_sellers_observation (category_key, market_date DESC, rank);

CREATE FUNCTION ingest_best_sellers_snapshot(p_payload jsonb)
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
            INSERT INTO best_sellers_observation (
                best_sellers_run_id, category_key, market_date, observed_at, asin, rank, title,
                source_url, price_text, price_amount, rating, review_count, source_page, payload_json
            ) VALUES (
                v_run_id, v_category_key, v_market_date, v_observed_at, upper(v_item->>'asin'),
                (v_item->>'rank')::integer, v_item->>'title', v_item->>'url', v_item->>'price',
                NULLIF(regexp_replace(COALESCE(v_item->>'price', ''), '[^0-9.]', '', 'g'), '')::numeric,
                NULLIF(v_item->>'rating', '')::numeric, NULLIF(v_item->>'reviews', '')::bigint,
                NULLIF(v_item->>'source_page', '')::integer, v_item
            ) ON CONFLICT (best_sellers_run_id, category_key, asin) DO NOTHING;
        END LOOP;
    END LOOP;
    RETURN v_run_id;
END;
$$;

CREATE VIEW best_sellers_daily_current AS
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
    o.price_text, o.price_amount, o.rating, o.review_count, o.source_page
FROM latest_source ls
JOIN best_sellers_observation o
  ON o.best_sellers_run_id = ls.best_sellers_run_id AND o.category_key = ls.category_key
WHERE ls.version_rank = 1;

CREATE VIEW best_sellers_daily_change AS
SELECT
    c.*,
    lag(c.rank) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) AS previous_rank,
    lag(c.rank) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) - c.rank AS rank_change,
    lag(c.market_date) OVER (PARTITION BY c.category_key, c.asin ORDER BY c.market_date) AS previous_seen_date
FROM best_sellers_daily_current c;

CREATE VIEW best_sellers_daily_exit AS
WITH category_dates AS (
    SELECT category_key, market_date,
           lag(market_date) OVER (PARTITION BY category_key ORDER BY market_date) AS previous_market_date
    FROM (SELECT DISTINCT category_key, market_date FROM best_sellers_daily_current) d
), exits AS (
    SELECT
        d.category_key, d.market_date, d.previous_market_date,
        p.asin, p.rank AS previous_rank, p.title, p.source_url
    FROM category_dates d
    JOIN best_sellers_daily_current p
      ON p.category_key = d.category_key AND p.market_date = d.previous_market_date
    LEFT JOIN best_sellers_daily_current c
      ON c.category_key = d.category_key AND c.market_date = d.market_date AND c.asin = p.asin
    WHERE d.previous_market_date IS NOT NULL AND c.asin IS NULL
)
SELECT * FROM exits;

COMMIT;
