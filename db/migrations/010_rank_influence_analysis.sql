BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE best_sellers_rank_influence_run (
    rank_influence_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    market_date date NOT NULL,
    generated_at timestamptz NOT NULL,
    model_version varchar(80) NOT NULL,
    history_day_count integer NOT NULL CHECK (history_day_count >= 0),
    source_artifact_path varchar(2000) NOT NULL,
    source_artifact_sha256 char(64) NOT NULL UNIQUE,
    payload_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE best_sellers_rank_association (
    rank_influence_run_id bigint NOT NULL REFERENCES best_sellers_rank_influence_run(rank_influence_run_id),
    category_key varchar(100) NOT NULL,
    analysis_scope varchar(30) NOT NULL,
    metric varchar(80) NOT NULL,
    outcome varchar(80) NOT NULL,
    sample_size integer NOT NULL CHECK (sample_size >= 0),
    status varchar(40) NOT NULL,
    spearman_rho numeric(7,4) CHECK (spearman_rho IS NULL OR spearman_rho BETWEEN -1 AND 1),
    direction varchar(80) NOT NULL,
    strength varchar(30) NOT NULL,
    PRIMARY KEY (rank_influence_run_id, category_key, analysis_scope, metric)
);

CREATE TABLE best_sellers_rank_bucket_summary (
    rank_influence_run_id bigint NOT NULL REFERENCES best_sellers_rank_influence_run(rank_influence_run_id),
    category_key varchar(100) NOT NULL,
    metric varchar(80) NOT NULL,
    bucket varchar(80) NOT NULL,
    item_count integer NOT NULL CHECK (item_count > 0),
    average_rank numeric(6,2) NOT NULL,
    top_10_count integer NOT NULL CHECK (top_10_count >= 0),
    top_10_share_percent numeric(5,2) NOT NULL CHECK (top_10_share_percent BETWEEN 0 AND 100),
    PRIMARY KEY (rank_influence_run_id, category_key, metric, bucket)
);

CREATE FUNCTION ingest_best_sellers_rank_influence(p_payload jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id bigint;
    v_category jsonb;
    v_association jsonb;
    v_bucket jsonb;
BEGIN
    IF p_payload->>'schema_version' <> 'best-sellers-rank-influence-v1' THEN
        RAISE EXCEPTION 'Unsupported rank influence schema version';
    END IF;
    INSERT INTO best_sellers_rank_influence_run (
        market_date, generated_at, model_version, history_day_count,
        source_artifact_path, source_artifact_sha256, payload_json
    ) VALUES (
        (p_payload->>'market_date')::date, (p_payload->>'generated_at')::timestamptz,
        p_payload->>'model_version', (p_payload->>'history_day_count')::integer,
        p_payload->>'source_artifact_path', p_payload->>'source_artifact_sha256', p_payload
    ) ON CONFLICT (source_artifact_sha256)
    DO UPDATE SET source_artifact_path = EXCLUDED.source_artifact_path
    RETURNING rank_influence_run_id INTO v_run_id;

    FOR v_category IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'categories', '[]'::jsonb))
    LOOP
        FOR v_association IN SELECT value FROM jsonb_array_elements(COALESCE(v_category->'cross_sectional_associations', '[]'::jsonb))
        LOOP
            INSERT INTO best_sellers_rank_association (
                rank_influence_run_id, category_key, analysis_scope, metric, outcome,
                sample_size, status, spearman_rho, direction, strength
            ) VALUES (
                v_run_id, v_category->>'category', 'CROSS_SECTIONAL', v_association->>'metric',
                v_association->>'outcome', (v_association->>'sample_size')::integer,
                v_association->>'status', NULLIF(v_association->>'spearman_rho', '')::numeric,
                v_association->>'direction', v_association->>'strength'
            ) ON CONFLICT DO NOTHING;
        END LOOP;
        FOR v_association IN SELECT value FROM jsonb_array_elements(COALESCE(v_category->'longitudinal_associations', '[]'::jsonb))
        LOOP
            INSERT INTO best_sellers_rank_association (
                rank_influence_run_id, category_key, analysis_scope, metric, outcome,
                sample_size, status, spearman_rho, direction, strength
            ) VALUES (
                v_run_id, v_category->>'category', 'LONGITUDINAL', v_association->>'metric',
                v_association->>'outcome', (v_association->>'sample_size')::integer,
                v_association->>'status', NULLIF(v_association->>'spearman_rho', '')::numeric,
                v_association->>'direction', v_association->>'strength'
            ) ON CONFLICT DO NOTHING;
        END LOOP;
        FOR v_bucket IN SELECT value FROM jsonb_array_elements(COALESCE(v_category->'bucket_summaries', '[]'::jsonb))
        LOOP
            INSERT INTO best_sellers_rank_bucket_summary (
                rank_influence_run_id, category_key, metric, bucket, item_count,
                average_rank, top_10_count, top_10_share_percent
            ) VALUES (
                v_run_id, v_category->>'category', v_bucket->>'metric', v_bucket->>'bucket',
                (v_bucket->>'item_count')::integer, (v_bucket->>'average_rank')::numeric,
                (v_bucket->>'top_10_count')::integer, (v_bucket->>'top_10_share_percent')::numeric
            ) ON CONFLICT DO NOTHING;
        END LOOP;
    END LOOP;
    RETURN v_run_id;
END;
$$;

CREATE VIEW best_sellers_rank_association_latest AS
WITH latest_run AS (
    SELECT *, row_number() OVER (PARTITION BY market_date ORDER BY generated_at DESC, rank_influence_run_id DESC) AS version_rank
    FROM best_sellers_rank_influence_run
)
SELECT r.market_date, r.generated_at, r.model_version, r.history_day_count, a.*
FROM latest_run r JOIN best_sellers_rank_association a USING (rank_influence_run_id)
WHERE r.version_rank = 1;

CREATE VIEW best_sellers_rank_bucket_latest AS
WITH latest_run AS (
    SELECT *, row_number() OVER (PARTITION BY market_date ORDER BY generated_at DESC, rank_influence_run_id DESC) AS version_rank
    FROM best_sellers_rank_influence_run
)
SELECT r.market_date, r.generated_at, r.model_version, b.*
FROM latest_run r JOIN best_sellers_rank_bucket_summary b USING (rank_influence_run_id)
WHERE r.version_rank = 1;

COMMIT;
