BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE TABLE best_sellers_analysis_run (
    best_sellers_analysis_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    period_start date NOT NULL,
    period_end date NOT NULL,
    generated_at timestamptz NOT NULL,
    model_version varchar(80) NOT NULL,
    source_artifact_path varchar(2000) NOT NULL,
    source_artifact_sha256 char(64) NOT NULL UNIQUE,
    snapshot_day_count integer NOT NULL CHECK (snapshot_day_count > 0),
    required_history_days integer NOT NULL CHECK (required_history_days > 1),
    coverage_complete boolean NOT NULL,
    payload_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (period_end >= period_start)
);

CREATE TABLE best_sellers_opportunity_signal (
    best_sellers_analysis_run_id bigint NOT NULL REFERENCES best_sellers_analysis_run(best_sellers_analysis_run_id),
    category_key varchar(100) NOT NULL,
    asin char(10) NOT NULL CHECK (asin ~ '^[A-Z0-9]{10}$'),
    end_rank integer CHECK (end_rank IS NULL OR end_rank BETWEEN 1 AND 100),
    observed_score numeric(5,2) CHECK (observed_score IS NULL OR observed_score BETWEEN 0 AND 100),
    confidence_percent numeric(5,2) NOT NULL CHECK (confidence_percent BETWEEN 0 AND 100),
    available_weight_percent integer NOT NULL CHECK (available_weight_percent BETWEEN 0 AND 100),
    classification varchar(40) NOT NULL,
    components jsonb NOT NULL,
    signals jsonb NOT NULL,
    missing_dimensions jsonb NOT NULL,
    evidence jsonb NOT NULL,
    title text NOT NULL,
    source_url varchar(2000),
    PRIMARY KEY (best_sellers_analysis_run_id, category_key, asin)
);

CREATE INDEX ix_best_sellers_analysis_period ON best_sellers_analysis_run (period_end DESC, generated_at DESC);
CREATE INDEX ix_best_sellers_opportunity_lookup ON best_sellers_opportunity_signal (category_key, classification, observed_score DESC);

CREATE FUNCTION ingest_best_sellers_opportunity_analysis(p_payload jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id bigint;
    v_category jsonb;
    v_product jsonb;
BEGIN
    IF p_payload->>'schema_version' <> 'best-sellers-opportunity-analysis-v1' THEN
        RAISE EXCEPTION 'Unsupported opportunity analysis schema version';
    END IF;

    INSERT INTO best_sellers_analysis_run (
        period_start, period_end, generated_at, model_version, source_artifact_path,
        source_artifact_sha256, snapshot_day_count, required_history_days,
        coverage_complete, payload_json
    ) VALUES (
        (p_payload->>'period_start')::date, (p_payload->>'period_end')::date,
        (p_payload->>'generated_at')::timestamptz, p_payload->>'model_version',
        p_payload->>'source_artifact_path', p_payload->>'source_artifact_sha256',
        (p_payload->>'snapshot_day_count')::integer,
        (p_payload->>'required_history_days')::integer,
        (p_payload->>'coverage_complete')::boolean, p_payload
    )
    ON CONFLICT (source_artifact_sha256)
    DO UPDATE SET source_artifact_path = EXCLUDED.source_artifact_path
    RETURNING best_sellers_analysis_run_id INTO v_run_id;

    FOR v_category IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'categories', '[]'::jsonb))
    LOOP
        FOR v_product IN SELECT value FROM jsonb_array_elements(COALESCE(v_category->'products', '[]'::jsonb))
        LOOP
            INSERT INTO best_sellers_opportunity_signal (
                best_sellers_analysis_run_id, category_key, asin, end_rank, observed_score,
                confidence_percent, available_weight_percent, classification, components,
                signals, missing_dimensions, evidence, title, source_url
            ) VALUES (
                v_run_id, v_category->>'category', upper(v_product->>'asin'),
                NULLIF(v_product->>'end_rank', '')::integer,
                NULLIF(v_product->>'observed_score', '')::numeric,
                (v_product->>'confidence_percent')::numeric,
                (v_product->>'available_weight_percent')::integer,
                v_product->>'classification', COALESCE(v_product->'components', '{}'::jsonb),
                COALESCE(v_product->'signals', '[]'::jsonb),
                COALESCE(v_product->'missing_dimensions', '[]'::jsonb),
                COALESCE(v_product->'evidence', '{}'::jsonb),
                v_product->>'title', NULLIF(v_product->>'url', '')
            ) ON CONFLICT (best_sellers_analysis_run_id, category_key, asin) DO NOTHING;
        END LOOP;
    END LOOP;
    RETURN v_run_id;
END;
$$;

CREATE VIEW best_sellers_opportunity_latest AS
WITH ranked_runs AS (
    SELECT r.*,
           row_number() OVER (PARTITION BY r.period_end ORDER BY r.generated_at DESC, r.best_sellers_analysis_run_id DESC) AS version_rank
    FROM best_sellers_analysis_run r
)
SELECT
    r.period_start, r.period_end, r.generated_at, r.model_version,
    r.snapshot_day_count, r.required_history_days, r.coverage_complete,
    s.category_key, s.asin, s.end_rank, s.observed_score, s.confidence_percent,
    s.available_weight_percent, s.classification, s.components, s.signals,
    s.missing_dimensions, s.evidence, s.title, s.source_url
FROM ranked_runs r
JOIN best_sellers_opportunity_signal s USING (best_sellers_analysis_run_id)
WHERE r.version_rank = 1;

COMMIT;
