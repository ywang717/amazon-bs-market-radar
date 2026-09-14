BEGIN;

CREATE SCHEMA IF NOT EXISTS amazon_intelligence;
SET search_path TO amazon_intelligence, public;

CREATE TYPE source_type AS ENUM ('BEST_SELLERS', 'MOVERS_SHAKERS', 'SEARCH');
CREATE TYPE run_status AS ENUM ('RUNNING', 'SUCCEEDED', 'FAILED', 'QUARANTINED');
CREATE TYPE fba_status AS ENUM ('FBA', 'FBM', 'AMAZON', 'UNKNOWN');
CREATE TYPE signal_type AS ENUM (
    'BASELINE', 'NEW_PRODUCT', 'NEW_BRAND', 'RISING_PRODUCT',
    'HIGH_RANK_LOW_REVIEW', 'LOW_COMPETITION', 'FAST_GROWING'
);
CREATE TYPE opportunity_level AS ENUM ('HIGH', 'MEDIUM', 'LOW');

CREATE TABLE marketplace (
    marketplace_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code varchar(32) NOT NULL UNIQUE,
    country_code char(2) NOT NULL,
    currency char(3) NOT NULL,
    timezone varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE category (
    category_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_category_id bigint REFERENCES category(category_id),
    name varchar(160) NOT NULL,
    slug varchar(160) NOT NULL UNIQUE,
    category_level smallint NOT NULL CHECK (category_level > 0),
    accessory_type varchar(64),
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE category_source_map (
    category_source_map_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marketplace_id bigint NOT NULL REFERENCES marketplace(marketplace_id),
    external_node_id varchar(128) NOT NULL,
    category_id bigint NOT NULL REFERENCES category(category_id),
    valid_from date NOT NULL,
    valid_to date,
    CHECK (valid_to IS NULL OR valid_to >= valid_from),
    UNIQUE (marketplace_id, external_node_id, valid_from)
);

CREATE TABLE source_definition (
    source_id uuid PRIMARY KEY,
    marketplace_id bigint NOT NULL REFERENCES marketplace(marketplace_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    source_type source_type NOT NULL,
    search_term varchar(300),
    target_limit integer NOT NULL CHECK (target_limit > 0),
    config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((source_type = 'SEARCH' AND search_term IS NOT NULL) OR source_type <> 'SEARCH')
);

CREATE TABLE brand (
    brand_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    canonical_name varchar(300) NOT NULL,
    normalized_key varchar(300) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE brand_alias (
    brand_alias_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alias_normalized varchar(300) NOT NULL,
    brand_id bigint NOT NULL REFERENCES brand(brand_id),
    valid_from date NOT NULL,
    valid_to date,
    CHECK (valid_to IS NULL OR valid_to >= valid_from),
    UNIQUE (alias_normalized, valid_from)
);

CREATE TABLE seller (
    seller_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marketplace_id bigint NOT NULL REFERENCES marketplace(marketplace_id),
    external_seller_id varchar(128),
    display_name varchar(500) NOT NULL,
    normalized_key varchar(500) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (marketplace_id, normalized_key)
);

CREATE TABLE product (
    product_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marketplace_id bigint NOT NULL REFERENCES marketplace(marketplace_id),
    asin char(10) NOT NULL CHECK (asin ~ '^[A-Z0-9]{10}$'),
    brand_id bigint REFERENCES brand(brand_id),
    model varchar(300),
    first_seen_at timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'ACTIVE',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (marketplace_id, asin),
    CHECK (last_seen_at >= first_seen_at)
);

CREATE TABLE product_category (
    product_category_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL REFERENCES product(product_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    valid_from date NOT NULL,
    valid_to date,
    confidence numeric(5,4) CHECK (confidence BETWEEN 0 AND 1),
    mapping_method varchar(64) NOT NULL,
    CHECK (valid_to IS NULL OR valid_to >= valid_from),
    UNIQUE (product_id, category_id, valid_from)
);

CREATE TABLE collection_run (
    run_id uuid PRIMARY KEY,
    source_id uuid NOT NULL REFERENCES source_definition(source_id),
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    status run_status NOT NULL,
    parser_version varchar(64) NOT NULL,
    expected_count integer NOT NULL CHECK (expected_count >= 0),
    raw_count integer NOT NULL DEFAULT 0 CHECK (raw_count >= 0),
    accepted_count integer NOT NULL DEFAULT 0 CHECK (accepted_count >= 0),
    rejected_count integer NOT NULL DEFAULT 0 CHECK (rejected_count >= 0),
    error_summary text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (finished_at IS NULL OR finished_at >= started_at),
    CHECK (accepted_count + rejected_count <= raw_count)
);

CREATE TABLE raw_artifact (
    artifact_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES collection_run(run_id),
    content_hash char(64) NOT NULL,
    storage_uri varchar(1000) NOT NULL,
    captured_at timestamptz NOT NULL,
    media_type varchar(100) NOT NULL,
    retention_status varchar(32) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (run_id, content_hash)
);

CREATE TABLE data_quality_issue (
    issue_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES collection_run(run_id),
    record_locator varchar(500),
    rule_code varchar(100) NOT NULL,
    severity varchar(16) NOT NULL CHECK (severity IN ('INFO', 'WARNING', 'ERROR')),
    details_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolution_status varchar(32) NOT NULL DEFAULT 'OPEN'
);

CREATE TABLE ranking_observation (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES collection_run(run_id),
    market_date date NOT NULL,
    observed_at timestamptz NOT NULL,
    source_id uuid NOT NULL REFERENCES source_definition(source_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    product_id bigint NOT NULL REFERENCES product(product_id),
    rank integer NOT NULL CHECK (rank > 0),
    source_badge varchar(160),
    page_position integer CHECK (page_position IS NULL OR page_position > 0),
    source_url varchar(2000) NOT NULL,
    record_key char(64) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, source_id, category_id, product_id)
);

CREATE TABLE offer_snapshot (
    offer_snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES collection_run(run_id),
    product_id bigint NOT NULL REFERENCES product(product_id),
    market_date date NOT NULL,
    observed_at timestamptz NOT NULL,
    price numeric(12,2) CHECK (price IS NULL OR price >= 0),
    currency char(3) NOT NULL,
    coupon_text varchar(500),
    coupon_value numeric(12,2) CHECK (coupon_value IS NULL OR coupon_value >= 0),
    seller_id bigint REFERENCES seller(seller_id),
    fba_status fba_status NOT NULL DEFAULT 'UNKNOWN',
    availability varchar(100),
    record_key char(64) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE listing_snapshot (
    listing_snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES collection_run(run_id),
    product_id bigint NOT NULL REFERENCES product(product_id),
    market_date date NOT NULL,
    observed_at timestamptz NOT NULL,
    title text NOT NULL,
    model varchar(300),
    rating numeric(2,1) CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
    review_count integer CHECK (review_count IS NULL OR review_count >= 0),
    first_available_date date,
    canonical_url varchar(2000) NOT NULL,
    content_hash char(64) NOT NULL,
    record_key char(64) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE listing_content_snapshot (
    listing_snapshot_id bigint PRIMARY KEY REFERENCES listing_snapshot(listing_snapshot_id),
    bullet_points jsonb NOT NULL DEFAULT '[]'::jsonb,
    image_refs jsonb NOT NULL DEFAULT '[]'::jsonb,
    description text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE review_snapshot (
    review_snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES collection_run(run_id),
    product_id bigint NOT NULL REFERENCES product(product_id),
    review_external_id varchar(200),
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_date date NOT NULL,
    title text,
    body text,
    verified boolean,
    content_hash char(64) NOT NULL,
    observed_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, content_hash)
);

CREATE TABLE daily_product_metric (
    market_date date NOT NULL,
    product_id bigint NOT NULL REFERENCES product(product_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    source_id uuid NOT NULL REFERENCES source_definition(source_id),
    current_rank integer CHECK (current_rank IS NULL OR current_rank > 0),
    previous_rank integer CHECK (previous_rank IS NULL OR previous_rank > 0),
    rank_change integer,
    price numeric(12,2),
    rating numeric(2,1),
    review_count integer,
    review_velocity_7d numeric(12,4),
    review_velocity_30d numeric(12,4),
    coverage_days integer NOT NULL CHECK (coverage_days > 0),
    calculation_version varchar(64) NOT NULL,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (market_date, product_id, category_id, source_id, calculation_version)
);

CREATE TABLE daily_brand_metric (
    market_date date NOT NULL,
    brand_id bigint NOT NULL REFERENCES brand(brand_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    product_count integer NOT NULL CHECK (product_count >= 0),
    top100_count integer NOT NULL CHECK (top100_count >= 0),
    rank_share numeric(8,6),
    growth_7d numeric(12,4),
    growth_30d numeric(12,4),
    growth_90d numeric(12,4),
    calculation_version varchar(64) NOT NULL,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (market_date, brand_id, category_id, calculation_version)
);

CREATE TABLE detection_signal (
    signal_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    market_date date NOT NULL,
    signal_type signal_type NOT NULL,
    product_id bigint REFERENCES product(product_id),
    brand_id bigint REFERENCES brand(brand_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    severity varchar(16) NOT NULL,
    evidence_json jsonb NOT NULL,
    rule_version varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (product_id IS NOT NULL OR brand_id IS NOT NULL)
);

CREATE TABLE score_model_version (
    model_version varchar(64) PRIMARY KEY,
    effective_from timestamptz NOT NULL,
    weights_json jsonb NOT NULL,
    thresholds_json jsonb NOT NULL,
    missing_policy_json jsonb NOT NULL,
    status varchar(32) NOT NULL
);

CREATE TABLE opportunity_score (
    market_date date NOT NULL,
    product_id bigint NOT NULL REFERENCES product(product_id),
    category_id bigint NOT NULL REFERENCES category(category_id),
    model_version varchar(64) NOT NULL REFERENCES score_model_version(model_version),
    rank_growth_score numeric(5,2) NOT NULL CHECK (rank_growth_score BETWEEN 0 AND 100),
    review_velocity_score numeric(5,2) NOT NULL CHECK (review_velocity_score BETWEEN 0 AND 100),
    rating_score numeric(5,2) NOT NULL CHECK (rating_score BETWEEN 0 AND 100),
    new_product_score numeric(5,2) NOT NULL CHECK (new_product_score BETWEEN 0 AND 100),
    brand_growth_score numeric(5,2) NOT NULL CHECK (brand_growth_score BETWEEN 0 AND 100),
    total_score numeric(5,2) NOT NULL CHECK (total_score BETWEEN 0 AND 100),
    level opportunity_level NOT NULL,
    evidence_json jsonb NOT NULL,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (market_date, product_id, category_id, model_version)
);

CREATE INDEX ix_ranking_category_source_date_rank
    ON ranking_observation (category_id, source_id, market_date, rank);
CREATE INDEX ix_ranking_product_date
    ON ranking_observation (product_id, market_date);
CREATE INDEX ix_offer_product_date
    ON offer_snapshot (product_id, market_date);
CREATE INDEX ix_listing_product_date
    ON listing_snapshot (product_id, market_date);
CREATE INDEX ix_review_product_date
    ON review_snapshot (product_id, review_date);
CREATE INDEX ix_brand_metric_category_date
    ON daily_brand_metric (brand_id, category_id, market_date);
CREATE INDEX ix_quality_open
    ON data_quality_issue (run_id, severity) WHERE resolution_status = 'OPEN';

COMMIT;
