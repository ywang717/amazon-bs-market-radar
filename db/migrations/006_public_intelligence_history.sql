BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE public_intelligence_run (
    public_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_key varchar(100) NOT NULL,
    market_date date NOT NULL,
    collected_at timestamptz NOT NULL,
    status varchar(16) NOT NULL CHECK (status IN ('SUCCEEDED', 'PARTIAL', 'FAILED')),
    lookback_days integer NOT NULL CHECK (lookback_days > 0),
    query_count integer NOT NULL CHECK (query_count >= 0),
    successful_query_count integer NOT NULL CHECK (successful_query_count >= 0),
    item_count integer NOT NULL CHECK (item_count >= 0),
    artifact_path varchar(2000) NOT NULL,
    query_results jsonb NOT NULL DEFAULT '[]'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_key, market_date),
    CHECK (successful_query_count <= query_count)
);

CREATE TABLE public_safety_notice (
    public_notice_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_key varchar(100) NOT NULL,
    external_notice_id varchar(200) NOT NULL,
    notice_date date NOT NULL,
    last_publish_at timestamptz,
    category_slug varchar(160) NOT NULL,
    title text NOT NULL,
    products text,
    manufacturers text,
    hazards text,
    remedies text,
    source_url varchar(2000) NOT NULL,
    first_seen_date date NOT NULL,
    last_seen_date date NOT NULL,
    current_content_hash char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_key, external_notice_id),
    CHECK (last_seen_date >= first_seen_date)
);

CREATE TABLE public_safety_notice_observation (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_run_id bigint NOT NULL REFERENCES public_intelligence_run(public_run_id),
    public_notice_id bigint NOT NULL REFERENCES public_safety_notice(public_notice_id),
    market_date date NOT NULL,
    observed_at timestamptz NOT NULL,
    content_hash char(64) NOT NULL,
    payload_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (public_run_id, public_notice_id, content_hash)
);

CREATE INDEX ix_public_notice_category_date ON public_safety_notice (category_slug, notice_date DESC);
CREATE INDEX ix_public_notice_seen ON public_safety_notice (last_seen_date DESC, first_seen_date DESC);
CREATE INDEX ix_public_observation_notice_date ON public_safety_notice_observation (public_notice_id, market_date DESC);

CREATE VIEW public_safety_current AS
SELECT
    n.source_key,
    n.external_notice_id,
    n.notice_date,
    n.last_publish_at,
    n.category_slug,
    n.title,
    n.products,
    n.manufacturers,
    n.hazards,
    n.remedies,
    n.source_url,
    n.first_seen_date,
    n.last_seen_date,
    count(o.observation_id) AS observation_version_count
FROM public_safety_notice n
LEFT JOIN public_safety_notice_observation o ON o.public_notice_id = n.public_notice_id
GROUP BY n.public_notice_id;

CREATE VIEW public_safety_daily_change AS
WITH versions AS (
    SELECT
        o.observation_id,
        o.market_date,
        o.public_notice_id,
        o.content_hash,
        lag(o.content_hash) OVER (
            PARTITION BY o.public_notice_id ORDER BY o.market_date, o.observed_at, o.observation_id
        ) AS previous_content_hash
    FROM public_safety_notice_observation o
)
SELECT
    v.market_date,
    n.source_key,
    n.external_notice_id,
    n.category_slug,
    n.title,
    n.source_url,
    (n.first_seen_date = v.market_date) AS first_seen_on_date,
    (v.previous_content_hash IS NOT NULL AND v.previous_content_hash <> v.content_hash) AS content_changed
FROM versions v
JOIN public_safety_notice n ON n.public_notice_id = v.public_notice_id;

CREATE FUNCTION ingest_public_intelligence(p_payload jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id bigint;
    v_notice_id bigint;
    v_item jsonb;
    v_market_date date := (p_payload->>'market_date')::date;
    v_source_key text := 'US_CPSC_RECALLS_API';
BEGIN
    IF p_payload->>'schema_version' <> 'cpsc-public-recall-intelligence-v1' THEN
        RAISE EXCEPTION 'Unsupported public intelligence schema version';
    END IF;

    INSERT INTO public_intelligence_run (
        source_key, market_date, collected_at, status, lookback_days,
        query_count, successful_query_count, item_count, artifact_path, query_results
    ) VALUES (
        v_source_key, v_market_date, (p_payload->>'collected_at')::timestamptz,
        p_payload->>'status', (p_payload->>'lookback_days')::integer,
        jsonb_array_length(COALESCE(p_payload->'query_results', '[]'::jsonb)),
        (SELECT count(*) FROM jsonb_array_elements(COALESCE(p_payload->'query_results', '[]'::jsonb)) q WHERE q->>'status' = 'SUCCEEDED'),
        jsonb_array_length(COALESCE(p_payload->'items', '[]'::jsonb)),
        p_payload->>'artifact_path', COALESCE(p_payload->'query_results', '[]'::jsonb)
    )
    ON CONFLICT (source_key, market_date) DO UPDATE SET
        collected_at = EXCLUDED.collected_at,
        status = EXCLUDED.status,
        lookback_days = EXCLUDED.lookback_days,
        query_count = EXCLUDED.query_count,
        successful_query_count = EXCLUDED.successful_query_count,
        item_count = EXCLUDED.item_count,
        artifact_path = EXCLUDED.artifact_path,
        query_results = EXCLUDED.query_results,
        updated_at = now()
    RETURNING public_run_id INTO v_run_id;

    FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'items', '[]'::jsonb))
    LOOP
        INSERT INTO public_safety_notice (
            source_key, external_notice_id, notice_date, last_publish_at, category_slug,
            title, products, manufacturers, hazards, remedies, source_url,
            first_seen_date, last_seen_date, current_content_hash
        ) VALUES (
            v_source_key, v_item->>'recall_number', (v_item->>'recall_date')::date,
            NULLIF(v_item->>'last_publish_date', '')::timestamptz, v_item->>'category_slug',
            v_item->>'title', v_item->>'products', v_item->>'manufacturers',
            v_item->>'hazards', v_item->>'remedies', v_item->>'url',
            v_market_date, v_market_date, v_item->>'content_hash'
        )
        ON CONFLICT (source_key, external_notice_id) DO UPDATE SET
            notice_date = EXCLUDED.notice_date,
            last_publish_at = EXCLUDED.last_publish_at,
            category_slug = EXCLUDED.category_slug,
            title = EXCLUDED.title,
            products = EXCLUDED.products,
            manufacturers = EXCLUDED.manufacturers,
            hazards = EXCLUDED.hazards,
            remedies = EXCLUDED.remedies,
            source_url = EXCLUDED.source_url,
            last_seen_date = GREATEST(public_safety_notice.last_seen_date, EXCLUDED.last_seen_date),
            current_content_hash = EXCLUDED.current_content_hash,
            updated_at = now()
        RETURNING public_notice_id INTO v_notice_id;

        INSERT INTO public_safety_notice_observation (
            public_run_id, public_notice_id, market_date, observed_at, content_hash, payload_json
        ) VALUES (
            v_run_id, v_notice_id, v_market_date, (p_payload->>'collected_at')::timestamptz,
            v_item->>'content_hash', v_item
        ) ON CONFLICT (public_run_id, public_notice_id, content_hash) DO NOTHING;
    END LOOP;
    RETURN v_run_id;
END;
$$;

COMMIT;
